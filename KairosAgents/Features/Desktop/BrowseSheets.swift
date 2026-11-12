import SwiftUI

/// The title row at the top of a Browse sheet, with a close button.
struct BrowseSheetHeader: View {
    let title: String
    var subtitle: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KFont.ui(22, .semibold, relativeTo: .title2))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            GlassIconButton(symbol: "xmark", label: "Close") { dismiss() }
        }
        .padding(.top, 30)
        .padding(.horizontal, 18)
    }
}

/// A grouped card of rows inside a Browse sheet.
private struct BrowseCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .kCard(radius: 20)
    }
}

/// A one-line row with an icon, words and something on the right.
private struct BrowseRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var tint: Color = Palette.goldText
    var last = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(2)
                if let detail {
                    Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 54)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 54) }
        }
    }
}

private struct SmallAction: View {
    let title: String
    var danger = false
    var filled = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(Motion.snappy) { action() }
        } label: {
            Text(title)
                .font(KFont.ui(14, .medium, relativeTo: .footnote))
                .foregroundStyle(filled ? Palette.onGold : (danger ? Palette.danger : Palette.ink))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(filled ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

private struct RoundAction: View {
    let symbol: String
    let label: String
    var tint: Color = Palette.inkDim
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(Motion.snappy) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

private struct BrowseSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.inkFaint)
            TextField(prompt, text: $text)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkFaint).frame(width: 36, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .kCard(radius: 24, raised: true)
    }
}

// MARK: - Tabs

struct BrowseTabsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var store: BrowseStore { .shared }
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BrowseSheetHeader(title: "Tabs", subtitle: "\(store.tabs.count) open on your PC")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(store.orderedTabs.enumerated()), id: \.element.id) { index, tab in
                        card(tab).arrives(index)
                    }
                }
                .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    DeskPillButton(title: "New tab", symbol: "plus", filled: true) {
                        store.openNewTab()
                        dismiss()
                    }
                    if !store.closed.isEmpty {
                        DeskPillButton(title: "Reopen closed tab", symbol: "arrow.uturn.backward") {
                            store.reopenClosed()
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 16)

                NoteLine(text: "Pinned tabs stay at the top. Tabs you have not used for a while sleep on your PC and reload when you open them.")
                    .padding(.horizontal, 18)
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .kSheet()
    }

    private func card(_ tab: BrowseTab) -> some View {
        let active = tab.id == store.activeID
        return Button {
            Haptics.select()
            store.select(tab.id)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                preview(tab)
                HStack(spacing: 5) {
                    if tab.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Palette.goldText) }
                    if !tab.holding.isEmpty { Circle().fill(Palette.danger).frame(width: 7, height: 7) }
                    if tab.muted {
                        Image(systemName: "speaker.slash.fill").font(.system(size: 10)).foregroundStyle(Palette.inkFaint)
                    } else if tab.audible {
                        Image(systemName: "speaker.wave.2.fill").font(.system(size: 10)).foregroundStyle(Palette.inkFaint)
                    }
                    Text(tab.shownTitle)
                        .font(KFont.ui(14, .medium, relativeTo: .footnote))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                Text(tab.isBlank ? "Speed Dial" : tab.host)
                    .font(KFont.ui(12.5, relativeTo: .caption))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                    .padding(.trailing, 30)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 20, raised: active)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(active ? Palette.gold : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.96))
        .accessibilityLabel("\(tab.shownTitle)\(active ? ", current tab" : "")\(tab.holding.isEmpty ? "" : ", using \(BrowseWords.devices(tab.holding))")")
        .overlay(alignment: .topTrailing) {
            RoundAction(symbol: "xmark", label: "Close \(tab.shownTitle)") { store.close(tab.id) }
        }
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button(tab.pinned ? "Unpin tab" : "Pin tab", systemImage: tab.pinned ? "pin.slash" : "pin") { store.togglePin(tab.id) }
                if !tab.isBlank {
                    Button(tab.muted ? "Unmute" : "Mute", systemImage: tab.muted ? "speaker.wave.2" : "speaker.slash") { store.toggleMute(tab.id) }
                    Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(tab.id) }
                }
                Button("Close", systemImage: "xmark", role: .destructive) { store.close(tab.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkDim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(tab.shownTitle) options")
        }
    }

    private func preview(_ tab: BrowseTab) -> some View {
        ZStack {
            if tab.isBlank {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surface2)
                Image(systemName: "square.grid.2x2").font(.system(size: 22)).foregroundStyle(Palette.goldText)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.paper)
                VStack(alignment: .leading, spacing: 5) {
                    Rectangle().fill(Color(hex: BrowseTabsSheet.tone(tab.host))).frame(height: 22)
                    Text(BrowseSample.text(for: tab.url))
                        .font(.system(size: 8))
                        .foregroundStyle(Palette.night.opacity(0.7))
                        .lineLimit(5)
                        .padding(.horizontal, 6)
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(height: 104)
        .accessibilityHidden(true)
    }

    nonisolated static func tone(_ host: String) -> UInt32 {
        let tones: [UInt32] = [Palette.botPowder, Palette.botSand, Palette.botRose, Palette.botSage, Palette.botLilac, Palette.botGold]
        return tones[host.unicodeScalars.reduce(0) { $0 + Int($1.value) } % tones.count]
    }
}

// MARK: - Site info

struct BrowseSiteSheet: View {
    let host: String
    let secure: Bool
    let blocked: Int
    let onSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ChromeState.self) private var chrome
    @State private var confirmReset = false
    private var store: BrowseStore { .shared }
    private var settings: SiteSettings { store.site(host) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BrowseSheetHeader(title: host, subtitle: "Site info")

                BrowseCard {
                    BrowseRow(symbol: secure ? "lock.fill" : "exclamationmark.triangle", title: secure ? "Secure" : "Not secure",
                              detail: secure ? "The connection to this site is encrypted." : "Anything you send here can be read on the way.",
                              tint: secure ? Palette.success : Palette.danger) { EmptyView() }
                    BrowseRow(symbol: "shield", title: "Ads and trackers",
                              detail: settings.adsBlocked ? "\(blocked) blocked on this page" : "Blocking is off here", last: true) {
                        SmallAction(title: settings.adsBlocked ? "Turn off here" : "Turn on here") {
                            store.setSite(host) { $0.adsBlocked.toggle() }
                            let on = store.site(host).adsBlocked
                            store.editActive { $0.blocked = on ? BrowseSample.blockedCount(for: "https://" + host, on: true) : 0 }
                            store.reload()
                        }
                    }
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Permissions")
                    BrowseCard {
                        ForEach(Array(SitePermission.allCases.enumerated()), id: \.element) { index, permission in
                            BrowseRow(symbol: permission.symbol, title: permission.rawValue, last: index == SitePermission.allCases.count - 1) {
                                Picker(permission.rawValue, selection: answerBinding(permission)) {
                                    ForEach(permission.answers, id: \.self) { Text($0.rawValue).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .tint(answerTint(settings.answer(permission)))
                            }
                        }
                    }
                    NoteLine(text: "Removing an answer or blocking it reloads pages on this site that hold the device.")
                }
                .padding(.horizontal, 16)

                BrowseCard {
                    BrowseRow(symbol: "rectangle.stack", title: "Pop-ups") {
                        Picker("Pop-ups", selection: Binding(get: { settings.popupsAllowed }, set: { value in store.setSite(host) { $0.popupsAllowed = value } })) {
                            Text("Only after a click").tag(false)
                            Text("Allow").tag(true)
                        }
                        .pickerStyle(.menu)
                        .tint(Palette.goldText)
                    }
                    BrowseRow(symbol: store.isPinned(host) ? "pin.fill" : "pin", title: store.isPinned(host) ? "Pinned on Speed Dial" : "Pin this site", last: true) {
                        if store.isPinned(host) {
                            SmallAction(title: "Unpin") { store.unpin(host: host) }
                        } else {
                            SmallAction(title: "Pin", filled: true) {
                                _ = store.pinSite(name: BrowseSample.title(for: "https://" + host), url: "https://" + host + "/")
                                chrome.say("Pinned to Speed Dial")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                VStack(spacing: 4) {
                    QuietButton(title: "All site settings") { onSettings() }
                    Button {
                        confirmReset = true
                    } label: {
                        Text("Reset this site")
                            .font(KFont.ui(16, .medium))
                            .foregroundStyle(Palette.danger)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
        .confirmationDialog("Reset \(host)?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                withAnimation(Motion.snappy) { store.sites[host] = nil }
                chrome.say("\(host) will ask again")
            }
        } message: {
            Text("Permissions, pop-ups, zoom and ad blocking go back to normal for this site.")
        }
    }

    private func answerBinding(_ permission: SitePermission) -> Binding<SiteAnswer> {
        Binding(
            get: { settings.answer(permission) },
            set: { value in
                Haptics.select()
                store.setSite(host) { $0.answers[permission] = value == .ask ? nil : value }
            }
        )
    }

    private func answerTint(_ answer: SiteAnswer) -> Color {
        switch answer {
        case .ask: Palette.inkDim
        case .allow: Palette.success
        case .block: Palette.danger
        }
    }
}

// MARK: - History

struct BrowseHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var confirmClear = false
    private var store: BrowseStore { .shared }

    private var visits: [HistoryVisit] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.history }
        return store.history.filter { $0.title.lowercased().contains(q) || $0.url.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BrowseSheetHeader(title: "History", subtitle: "The last 200 visits on your PC")
                BrowseSearchField(prompt: "Search history", text: $query)
                    .padding(.horizontal, 16)

                if visits.isEmpty {
                    DeskEmptyNote(symbol: "clock", title: query.isEmpty ? "Nothing in history yet" : "No matches",
                              text: query.isEmpty ? "Pages you open in Browse show up here." : "Nothing in history matches that.")
                } else {
                    BrowseCard {
                        ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                            HStack(spacing: 0) {
                                Button {
                                    store.go(visit.url, newTab: true)
                                    dismiss()
                                } label: {
                                    BrowseRow(symbol: "globe", title: visit.title, detail: "\(visit.host) · \(visit.when)", last: true) { EmptyView() }
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle(scale: 0.99))
                                RoundAction(symbol: "xmark", label: "Delete \(visit.title) from history") { store.deleteVisit(visit.id) }
                                    .padding(.trailing, 6)
                            }
                            .overlay(alignment: .bottom) {
                                if index < visits.count - 1 { Palette.line.frame(height: 1).padding(.leading, 54) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Button {
                    confirmClear = true
                } label: {
                    Label("Clear the last hour", systemImage: "trash")
                        .font(KFont.ui(16, .medium))
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .kSheet()
        .confirmationDialog("Clear the last hour?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { withAnimation(Motion.snappy) { store.clearLastHour() } }
        } message: {
            Text("Visits from the past hour are removed from your PC. This can't be undone.")
        }
    }
}

// MARK: - Downloads

struct BrowseDownloadsSheet: View {
    @Environment(ChromeState.self) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var store: BrowseStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BrowseSheetHeader(title: "Downloads", subtitle: "Saved to the Downloads folder on your PC")
                if store.downloads.isEmpty {
                    DeskEmptyNote(symbol: "arrow.down.circle", title: "No downloads yet", text: "Files you download in Browse show up here.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(store.downloads) { item in
                            row(item)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                NoteLine(text: "Removing an entry keeps the file on your PC.")
                    .padding(.horizontal, 18)
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.7))
                withAnimation(reduceMotion ? nil : Motion.gentle) { store.tickDownloads() }
            }
        }
    }

    private func row(_ item: BrowseDownload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(symbol: symbol(item.state), size: 42, tint: tint(item.state))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text("\(item.host) · \(item.state.label)")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let progress = progress(item.state) {
                ProgressView(value: Double(progress), total: 100).tint(Palette.gold)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    switch item.state {
                    case .downloading:
                        SmallAction(title: "Pause") { store.pause(item.id) }
                        SmallAction(title: "Cancel", danger: true) { store.cancel(item.id) }
                    case .paused:
                        SmallAction(title: "Resume", filled: true) { store.resume(item.id) }
                        SmallAction(title: "Cancel", danger: true) { store.cancel(item.id) }
                    case .done:
                        SmallAction(title: "Open on PC", filled: true) { chrome.say("Opening \(item.name) on your PC") }
                        SmallAction(title: "Show in folder") { chrome.say("Showing \(item.name) in its folder on your PC") }
                        SmallAction(title: "Remove") { store.removeDownload(item.id) }
                    case .cancelled, .failed:
                        SmallAction(title: "Remove") { store.removeDownload(item.id) }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .kCard(radius: 20)
        .accessibilityElement(children: .contain)
    }

    private func progress(_ state: DownloadState) -> Int? {
        switch state {
        case .downloading(let p), .paused(let p): return p
        default: return nil
        }
    }

    private func symbol(_ state: DownloadState) -> String {
        switch state {
        case .downloading: "arrow.down"
        case .paused: "pause"
        case .done: "checkmark"
        case .cancelled: "xmark"
        case .failed: "exclamationmark.triangle"
        }
    }

    private func tint(_ state: DownloadState) -> Color {
        switch state {
        case .done: Palette.success
        case .failed: Palette.danger
        case .cancelled: Palette.inkFaint
        default: Palette.goldText
        }
    }
}

// MARK: - Passwords

struct BrowsePasswordsSheet: View {
    @State private var query = ""
    @State private var pendingDelete: BrowseLogin?
    private var store: BrowseStore { .shared }

    private var logins: [BrowseLogin] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.logins }
        return store.logins.filter { $0.host.lowercased().contains(q) || $0.user.lowercased().contains(q) }
    }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BrowseSheetHeader(title: "Passwords", subtitle: "\(store.logins.count) saved on your PC")

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield").font(.system(size: 20)).foregroundStyle(Palette.goldText)
                    Text("Passwords never leave your PC. Show, copy, add, edit and import them in Browse on your PC.")
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                }
                .padding(14)
                .kCard(radius: 18, raised: true)
                .padding(.horizontal, 16)

                BrowseSearchField(prompt: "Search passwords", text: $query)
                    .padding(.horizontal, 16)

                if logins.isEmpty {
                    DeskEmptyNote(symbol: "key", title: query.isEmpty ? "No saved passwords yet" : "No matches",
                              text: query.isEmpty ? "Sign in to a site in Browse and choose Save." : "No saved password matches that.")
                } else {
                    BrowseCard {
                        ForEach(Array(logins.enumerated()), id: \.element.id) { index, login in
                            BrowseRow(symbol: "key", title: "\(login.host) · \(login.user)", detail: login.lastUsed, last: index == logins.count - 1) {
                                RoundAction(symbol: "trash", label: "Delete the password for \(login.user) on \(login.host)", tint: Palette.danger) {
                                    pendingDelete = login
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Never saved for")
                    if store.neverSave.isEmpty {
                        NoteLine(text: "Every site can offer to save a password.")
                    } else {
                        BrowseCard {
                            ForEach(Array(store.neverSave.enumerated()), id: \.element) { index, host in
                                BrowseRow(symbol: "nosign", title: host, last: index == store.neverSave.count - 1) {
                                    SmallAction(title: "Remove") { store.removeNever(host) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Bots")
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $store.botsUseLogins) {
                            Text("Let bots use saved passwords").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        }
                        .tint(Palette.gold)
                        Text("Your bots can sign in with these on the exact site each was saved for. They never see a password, and every use is listed here.")
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .padding(14)
                    .kCard(radius: 20)

                    if store.botUses.isEmpty {
                        NoteLine(text: "No bot has used a saved password yet.")
                    } else {
                        BrowseCard {
                            ForEach(Array(store.botUses.enumerated()), id: \.element.id) { index, use in
                                BrowseRow(symbol: "person.crop.circle", title: "\(use.bot) signed in to \(use.host)", detail: "\(use.user) · \(use.when)", last: index == store.botUses.count - 1) { EmptyView() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .kSheet()
        .confirmationDialog(
            "Delete saved password",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { login in
            Button("Delete", role: .destructive) {
                withAnimation(Motion.snappy) { store.deleteLogin(login.id) }
            }
        } message: { login in
            Text("\(login.user) on \(login.host). This can't be undone.")
        }
    }
}

// MARK: - Ask Kairos

struct BrowseAskSheet: View {
    let tab: BrowseTab
    @Environment(ChromeState.self) private var chrome
    @State private var question = ""
    @State private var messages: [ChatMessage] = []
    @FocusState private var typing: Bool

    private let quick = ["Summarise this page", "What are the key points?", "What should I do next?"]

    var body: some View {
        VStack(spacing: 0) {
            BrowseSheetHeader(title: "Ask Kairos", subtitle: "About this page")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        IconTile(symbol: "globe", size: 42)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tab.shownTitle).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(tab.host).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .kCard(radius: 18)

                    if messages.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(quick, id: \.self) { text in
                                    Button { ask(text) } label: { Chip(text: text, symbol: "sparkle", filled: false) }
                                        .buttonStyle(PressStyle())
                                        .frame(minHeight: 44)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }

                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                    }

                    Button {
                        Haptics.success()
                        chrome.say("Shared with Kairos. It is in a new chat.")
                    } label: {
                        Label("Share this page with Kairos", systemImage: "square.and.arrow.up.on.square")
                            .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.goldText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about this page", text: $question, axis: .vertical)
                    .font(KFont.ui(16.5))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1...4)
                    .focused($typing)
                    .padding(.vertical, 12)
                    .onSubmit { ask(question) }
                Button { ask(question) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.onGold)
                        .frame(width: 34, height: 34)
                        .background(Palette.gold, in: Circle())
                        .frame(width: 44, height: 48)
                }
                .buttonStyle(PressStyle(scale: 0.88))
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Ask")
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .kGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .kSheet([.medium, .large])
    }

    private func ask(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        Haptics.tap()
        question = ""
        withAnimation(Motion.bouncy) { messages.append(ChatMessage(kind: .mine(q))) }
        let page = BrowseSample.text(for: tab.url)
        let sentences = page.split(separator: ".").prefix(3).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(Motion.snappy) { messages.append(ChatMessage(kind: .status("Kairos is reading the page"))) }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(Motion.bouncy) {
                messages.removeAll { if case .status = $0.kind { return true } else { return false } }
                messages.append(ChatMessage(kind: .theirs("From \(tab.shownTitle): " + sentences.joined(separator: ". ") + ". This is sample data. Connect your desktop for a real answer.")))
            }
        }
    }
}

// MARK: - Browser settings

struct BrowseSettingsSheet: View {
    let onPasswords: () -> Void
    @Environment(ChromeState.self) private var chrome
    private var store: BrowseStore { .shared }

    private var rememberedHosts: [String] {
        store.sites.keys.filter { !(store.sites[$0]?.remembered.isEmpty ?? true) }.sorted()
    }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BrowseSheetHeader(title: "Browser settings", subtitle: "Browse on your PC")

                group("Search and sound") {
                    BrowseRow(symbol: "magnifyingglass", title: "Search engine") {
                        Picker("Search engine", selection: $store.engine) {
                            ForEach(SearchEngine.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(Palette.goldText)
                    }
                    BrowseRow(symbol: "speaker.wave.2", title: "Play pages through", detail: "Sites can see the names of your sound outputs.", last: true) {
                        Picker("Sound output", selection: $store.soundOutput) {
                            ForEach(store.soundOutputs, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(Palette.goldText)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Site permissions")
                    if rememberedHosts.isEmpty {
                        NoteLine(text: "No site has a remembered answer. Sites ask again each time until you choose Always allow or Block.")
                    } else {
                        BrowseCard {
                            ForEach(Array(rememberedHosts.enumerated()), id: \.element) { index, host in
                                BrowseRow(symbol: "globe", title: host, detail: summary(host), last: index == rememberedHosts.count - 1) {
                                    SmallAction(title: "Remove") {
                                        store.setSite(host) { $0.answers = [:] }
                                        chrome.say("\(host) will ask again")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                group("Passwords and blocking") {
                    Button(action: onPasswords) {
                        BrowseRow(symbol: "key", title: "Passwords", detail: "\(store.logins.count) saved") {
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint).padding(.trailing, 8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                    BrowseRow(symbol: "shield", title: "Ad blocking",
                              detail: "48,210 blocking rules and 12,904 hiding rules from 3 lists. 1,120 rules this blocker can't apply are skipped. Lists update every 6 hours.",
                              last: true) { EmptyView() }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Look on your PC")
                    BrowseCard {
                        BrowseRow(symbol: "paintbrush", title: "Browse look") {
                            Picker("Browse look", selection: $store.look) {
                                ForEach(BrowseLook.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(Palette.goldText)
                        }
                        Toggle(isOn: $store.chameleon) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Blend with the open site").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                Text("The sidebar and background take the site's colour.").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                            }
                        }
                        .tint(Palette.gold)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 60)
                    }
                    NoteLine(text: "Only Browse on your PC changes. The rest of Kairos keeps its own look.")
                }
                .padding(.horizontal, 16)

                NoteLine(text: "Printing, developer tools, importing passwords and picking a screen to share happen on your PC.", symbol: "desktopcomputer")
                    .padding(.horizontal, 18)
            }
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .kSheet()
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            VStack(spacing: 0) { content() }.kCard(radius: 20)
        }
        .padding(.horizontal, 16)
    }

    private func summary(_ host: String) -> String {
        let settings = store.site(host)
        return settings.remembered.map { p in
            "\(p.rawValue): \(settings.answer(p) == .allow ? "Always allowed" : "Blocked")"
        }.joined(separator: " · ")
    }
}

// MARK: - Customize home

struct BrowseHomeSheet: View {
    private var store: BrowseStore { .shared }

    var body: some View {
        @Bindable var store = store
        FittedSheet(estimate: 560) {
            VStack(alignment: .leading, spacing: 18) {
                BrowseSheetHeader(title: "Customize home", subtitle: "The new tab page on your PC")
                    .padding(.horizontal, -18)

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Background")
                    GlassSwitch(items: HomeBackground.allCases, selection: $store.home.background) { $0.rawValue }
                    if store.home.background == .picture {
                        NoteLine(text: "Choose the picture on your PC. JPEG, PNG or WEBP.")
                    }
                    if store.home.background != .kairos {
                        HStack {
                            Text("Dim the background").font(KFont.ui(15)).foregroundStyle(Palette.ink)
                            Slider(value: $store.home.dim, in: 0...0.9).tint(Palette.gold)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Tiles")
                    GlassSwitch(items: TileSize.allCases, selection: $store.home.tiles) { $0.rawValue }
                }

                VStack(spacing: 0) {
                    Toggle(isOn: $store.home.showSearch) { Text("Search box").font(KFont.ui(16)).foregroundStyle(Palette.ink) }
                        .tint(Palette.gold)
                        .frame(minHeight: 50)
                    Palette.line.frame(height: 1)
                    Toggle(isOn: $store.home.showSuggestions) { Text("Suggestions").font(KFont.ui(16)).foregroundStyle(Palette.ink) }
                        .tint(Palette.gold)
                        .frame(minHeight: 50)
                }
                .padding(.horizontal, 16)
                .kCard(radius: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Bot work

struct BrowseBotWorkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    private var store: BrowseStore { .shared }

    var body: some View {
        FittedSheet(estimate: 360) {
            VStack(alignment: .leading, spacing: 16) {
                BrowseSheetHeader(title: "Bot work", subtitle: "Bots browsing in their own computers")
                if store.botWork.isEmpty {
                    DeskEmptyNote(symbol: "person.2", title: "No bots are browsing", text: "When a bot opens a page in its own computer, it shows here.")
                } else {
                    BrowseCard {
                        ForEach(Array(store.botWork.enumerated()), id: \.element.id) { index, work in
                            Button {
                                dismiss()
                                router.push(.bot(work.botID), on: .home)
                            } label: {
                                HStack(spacing: 12) {
                                    BotFace(bot: SampleData.bot(work.botID), size: 40, showStatus: true)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(work.bot).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                                        Text(work.page).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    PulsingDot(color: Palette.working, size: 7)
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 62)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if index < store.botWork.count - 1 { Palette.line.frame(height: 1).padding(.leading, 68) }
                                }
                            }
                            .buttonStyle(PressStyle(scale: 0.99))
                            .accessibilityLabel("\(work.bot): \(work.page). Open the chat")
                        }
                    }
                    .padding(.horizontal, 16)
                }
                NoteLine(text: "These are the bots' own browsers, not your tabs. Open one to watch it or take over.")
                    .padding(.horizontal, 18)
            }
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Add or edit a Speed Dial site

struct BrowseSiteForm: View {
    let site: SpeedSite?
    @Environment(\.dismiss) private var dismiss
    @Environment(ChromeState.self) private var chrome
    @State private var name = ""
    @State private var address = ""
    @State private var problem: String?
    private var store: BrowseStore { .shared }

    var body: some View {
        FittedSheet(estimate: 460) {
            VStack(alignment: .leading, spacing: 16) {
                BrowseSheetHeader(title: site == nil ? "Add a site" : "Edit site", subtitle: "Speed Dial")
                    .padding(.horizontal, -18)
                field("Name", text: $name, prompt: "Riverside Bikes")
                field("Address", text: $address, prompt: "riverside-bikes.example")
                if let problem {
                    Text(problem).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.danger)
                }
                GoldButton(title: site == nil ? "Add" : "Save") { save() }
                if let site {
                    HStack(spacing: 8) {
                        DeskPillButton(title: "Open in a new tab", symbol: "plus.square.on.square") {
                            store.go(site.url, newTab: true)
                            dismiss()
                        }
                        DeskPillButton(title: "Refresh picture", symbol: "arrow.clockwise") {
                            chrome.say("The picture updates the next time you open the site.")
                        }
                    }
                    Button {
                        Haptics.thud()
                        withAnimation(Motion.snappy) { store.removeSite(site.id) }
                        dismiss()
                    } label: {
                        Text("Remove from Speed Dial")
                            .font(KFont.ui(16, .medium))
                            .foregroundStyle(Palette.danger)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .onAppear {
            if let site, name.isEmpty {
                name = site.name
                address = site.url
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            TextField(prompt, text: text)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .kCard(radius: 16, raised: true)
                .onChange(of: text.wrappedValue) { problem = nil }
        }
    }

    private func save() {
        let ok: Bool
        if let site {
            ok = store.editSite(site.id, name: name, url: address)
        } else {
            ok = store.pinSite(name: name, url: address)
        }
        if ok {
            Haptics.success()
            dismiss()
        } else {
            withAnimation(Motion.snappy) { problem = "That address can't be used." }
        }
    }
}
