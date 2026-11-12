import SwiftUI
import WebKit

/// The sheets Browse can open, and the state a debug picture can open on.
nonisolated enum BrowseSheet: Identifiable, Hashable, Sendable {
    case tabs, site, history, downloads, passwords, ask, settings, customize, botWork, addSite
    case editSite(SpeedSite)

    var id: String {
        switch self {
        case .tabs: "tabs"
        case .site: "site"
        case .history: "history"
        case .downloads: "downloads"
        case .passwords: "passwords"
        case .ask: "ask"
        case .settings: "settings"
        case .customize: "customize"
        case .botWork: "botWork"
        case .addSite: "addSite"
        case .editSite(let site): "edit-" + site.id
        }
    }
}

/// The desktop browser, from the phone: the PC's Browse tabs, one page at a time,
/// with the address bar and controls at the bottom where a thumb reaches them.
struct BrowseScreen: View {
    var start: BrowseSheet? = nil
    var startFinding = false

    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var sheet: BrowseSheet?
    @State private var started = false
    @State private var draft = ""
    @FocusState private var addressFocused: Bool
    @State private var finding = false
    @State private var findText = ""
    @State private var findIndex = 0
    @State private var findRequest = BrowseFind(id: 0, text: "", backward: false)
    @State private var zooming = false
    @State private var homeQuery = ""
    @State private var editingDial = false

    private var store: BrowseStore { .shared }
    private var tab: BrowseTab { store.active }

    var body: some View {
        VStack(spacing: 8) {
            strips
            page
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .kScreen(glowAt: UnitPoint(x: 0.15, y: -0.05))
        .animation(Motion.snappy, value: tab.prompt)
        .animation(Motion.snappy, value: tab.holding)
        .animation(Motion.snappy, value: tab.offer)
        .animation(Motion.snappy, value: finding)
        .animation(Motion.snappy, value: zooming)
        .sheet(item: $sheet) { item in
            sheetView(item)
                .environment(router)
                .environment(chrome)
        }
        .onAppear {
            draft = tab.host
            guard !started else { return }
            started = true
            if startFinding {
                finding = true
                findText = "bike"
                runFind(backward: false)
            }
            if let start { sheet = start }
        }
        .onChange(of: addressFocused) { _, focused in
            draft = focused ? tab.url : tab.host
        }
        .onChange(of: tab.url) {
            if !addressFocused { draft = tab.host }
            finding = false
            zooming = false
        }
        .onChange(of: store.activeID) {
            draft = tab.host
            finding = false
            zooming = false
        }
    }

    // MARK: Header

    private var header: some View {
        ScreenHeader(title: tab.shownTitle, subtitle: tab.isBlank ? "Browse on your PC" : tab.host) {
            if let url = URL(string: tab.url), !tab.isBlank {
                ShareLink(item: url, subject: Text(tab.shownTitle)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("Share this page")
            }
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            if !tab.isBlank {
                Section {
                    Button("Find on page", systemImage: "text.magnifyingglass") {
                        zooming = false
                        finding = true
                    }
                    Button("Zoom", systemImage: "plus.magnifyingglass") {
                        finding = false
                        zooming = true
                    }
                    Button("Site info", systemImage: "info.circle") { sheet = .site }
                }
            }
            Section {
                Button("New tab", systemImage: "plus.square") { store.openNewTab() }
                if !store.closed.isEmpty {
                    Button("Reopen closed tab", systemImage: "arrow.uturn.backward") { store.reopenClosed() }
                }
            }
            Section {
                Button("History", systemImage: "clock") { sheet = .history }
                Button("Downloads", systemImage: "arrow.down.circle") { sheet = .downloads }
                Button("Passwords", systemImage: "key") { sheet = .passwords }
                Button("Bot work", systemImage: "person.2") { sheet = .botWork }
                Button("Customize home", systemImage: "slider.horizontal.3") { sheet = .customize }
                Button("Browser settings", systemImage: "gearshape") { sheet = .settings }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .kGlass(Circle(), interactive: true)
        .accessibilityLabel("More")
    }

    // MARK: Strips above the page

    private var strips: some View {
        VStack(spacing: 8) {
            if let prompt = tab.prompt { promptStrip(prompt) }
            if !tab.holding.isEmpty { inUseStrip }
            if let offer = tab.offer { offerStrip(offer) }
            if let popup = tab.popup { popupStrip(popup) }
            if let notice = tab.notice {
                strip {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.danger)
                        Text(notice).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                        closeButton("Close notice") { store.editActive { $0.notice = nil } }
                    }
                }
            }
            if finding && !tab.isBlank { findBar }
            if zooming && !tab.isBlank { zoomBar }
        }
        .padding(.horizontal, 12)
    }

    private func strip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 18, raised: true)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func closeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(Motion.snappy) { action() }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.inkDim)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    private func smallButton(_ title: String, filled: Bool = false, danger: Bool = false, action: @escaping () -> Void) -> some View {
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

    private func promptStrip(_ prompt: BrowsePrompt) -> some View {
        strip {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: prompt.devices.contains("camera") ? "video" : "mic")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(prompt.site) wants to use your \(BrowseWords.devices(prompt.devices))")
                            .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.ink)
                        Text("This is the site asking, not Kairos. The answer is used on your PC.")
                            .font(KFont.ui(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { promptButtons }
                    VStack(alignment: .leading, spacing: 8) { promptButtons }
                }
            }
        }
    }

    @ViewBuilder
    private var promptButtons: some View {
        smallButton("Block", danger: true) { store.answerPrompt(.block, always: true) }
        smallButton("Allow once") { store.answerPrompt(.allow, always: false) }
        smallButton("Always allow", filled: true) { store.answerPrompt(.allow, always: true) }
    }

    private var inUseStrip: some View {
        strip {
            HStack(spacing: 10) {
                PulsingDot(color: Palette.danger, size: 8)
                Text("\(tab.host) has your \(BrowseWords.devices(tab.holding)) on this page. Stop reloads the page to end it.")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                smallButton("Stop", danger: true) { store.stopDevices() }
            }
        }
    }

    private func offerStrip(_ offer: PasswordOffer) -> some View {
        strip {
            if offer.saved {
                Label("Saved for \(offer.host).", systemImage: "checkmark.circle")
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.success)
                    .frame(minHeight: 30)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "key").foregroundStyle(Palette.goldText)
                        Text("Save the password for \(offer.user) on \(offer.host)?")
                            .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.ink)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { offerButtons }
                        VStack(alignment: .leading, spacing: 8) { offerButtons }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var offerButtons: some View {
        smallButton("Never for this site") { store.answerOffer(save: false, never: true) }
        smallButton("Not now") { store.answerOffer(save: false, never: false) }
        smallButton("Save", filled: true) { store.answerOffer(save: true, never: false) }
    }

    private func popupStrip(_ url: String) -> some View {
        strip {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack").foregroundStyle(Palette.goldText)
                Text("Pop-up blocked: \(BrowseAddress.host(of: url))")
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
                smallButton("Open it") { store.openPopup() }
                closeButton("Close notice") { store.editActive { $0.popup = nil } }
            }
        }
    }

    private var findCount: Int { BrowseWords.matches(findText, in: BrowseSample.text(for: tab.url)) }

    private var findBar: some View {
        strip {
            HStack(spacing: 6) {
                Image(systemName: "text.magnifyingglass").foregroundStyle(Palette.inkFaint)
                TextField("Find on page", text: $findText)
                    .font(KFont.ui(15.5))
                    .foregroundStyle(Palette.ink)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { step(forward: true) }
                    .onChange(of: findText) {
                        findIndex = 0
                        runFind(backward: false)
                    }
                Text(findText.isEmpty ? "" : (findCount == 0 ? "No matches" : "\(findIndex + 1) of \(findCount)"))
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .monospacedDigit()
                    .fixedSize()
                iconButton("chevron.up", "Previous match") { step(forward: false) }
                    .disabled(findCount == 0)
                iconButton("chevron.down", "Next match") { step(forward: true) }
                    .disabled(findCount == 0)
                closeButton("Close find") {
                    finding = false
                    findText = ""
                    runFind(backward: false)
                }
            }
        }
    }

    private func step(forward: Bool) {
        guard findCount > 0 else { return }
        findIndex = (findIndex + (forward ? 1 : findCount - 1)) % findCount
        runFind(backward: !forward)
    }

    private func runFind(backward: Bool) {
        findRequest = BrowseFind(id: findRequest.id + 1, text: findText, backward: backward)
    }

    private var zoomBar: some View {
        let zoom = store.site(tab.host).zoom
        return strip {
            HStack(spacing: 4) {
                Image(systemName: "plus.magnifyingglass").foregroundStyle(Palette.inkFaint)
                Text("Zoom")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .lineLimit(1)
                Spacer(minLength: 0)
                iconButton("minus", "Zoom out") { setZoom(BrowseWords.zoomStep(zoom, up: false)) }
                    .disabled(zoom <= 25)
                Text("\(zoom)%")
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 48)
                iconButton("plus", "Zoom in") { setZoom(BrowseWords.zoomStep(zoom, up: true)) }
                    .disabled(zoom >= 500)
                if zoom != 100 { smallButton("Reset") { setZoom(100) } }
                closeButton("Close zoom") { zooming = false }
            }
        }
    }

    private func setZoom(_ value: Int) {
        let host = tab.host
        withAnimation(Motion.snappy) { store.setSite(host) { $0.zoom = value } }
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    // MARK: Page

    @ViewBuilder
    private var page: some View {
        if tab.isBlank {
            speedDial
        } else {
            BrowsePageView(html: BrowseSample.html(for: tab.url), zoom: store.site(tab.host).zoom, find: findRequest)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .overlay(alignment: .top) {
                    if store.loading {
                        HStack(spacing: 8) {
                            ProgressView().tint(Palette.gold)
                            Text("Loading").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .kGlass(Capsule())
                        .padding(.top, 10)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 10)
                .accessibilityLabel("Page: \(tab.shownTitle)")
        }
    }

    private var tileColumns: [GridItem] {
        let count: Int
        switch store.home.tiles {
        case .small: count = 4
        case .medium: count = 3
        case .large: count = 2
        }
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var speedDial: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Where to?")
                    .font(KFont.display(36))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 6)
                    .arrives(0)

                if store.home.showSearch {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.inkFaint)
                        TextField("Search \(store.engine.rawValue) or type an address", text: $homeQuery)
                            .font(KFont.ui(16))
                            .foregroundStyle(Palette.ink)
                            .submitLabel(.go)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { open(homeQuery) { homeQuery = "" } }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .kCard(radius: 26, raised: true)
                    .arrives(1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "Speed Dial", action: editingDial ? "Done" : "Edit") {
                        withAnimation(Motion.snappy) { editingDial.toggle() }
                    }
                    if editingDial {
                        NoteLine(text: "Tap a site to rename it, change its address or remove it.", symbol: "hand.tap")
                    }
                    LazyVGrid(columns: tileColumns, spacing: 10) {
                        ForEach(store.speedDial) { site in
                            tile(site)
                        }
                        Button {
                            Haptics.tap()
                            sheet = .addSite
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "plus").font(.system(size: 20, weight: .semibold))
                                Text("Add a site").font(KFont.ui(13, relativeTo: .footnote))
                            }
                            .foregroundStyle(Palette.inkDim)
                            .frame(maxWidth: .infinity, minHeight: tileHeight)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.lineStrong, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Add a site to Speed Dial")
                    }
                }
                .arrives(2)

                if store.home.showSuggestions && !store.topSites.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Suggestions")
                        VStack(spacing: 0) {
                            ForEach(Array(store.topSites.enumerated()), id: \.element.id) { index, visit in
                                HStack(spacing: 0) {
                                    Button {
                                        store.go(visit.url)
                                    } label: {
                                        CardRow(symbol: "globe", title: visit.title, detail: visit.host, last: true, chevron: false)
                                    }
                                    .buttonStyle(PressStyle(scale: 0.99))
                                    Button {
                                        Haptics.success()
                                        withAnimation(Motion.snappy) { _ = store.pinSite(name: visit.title, url: visit.url) }
                                        chrome.say("Added to Speed Dial")
                                    } label: {
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(Palette.goldText)
                                            .frame(width: 52, height: 52)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressStyle())
                                    .accessibilityLabel("Add \(visit.title) to Speed Dial")
                                }
                                .overlay(alignment: .bottom) {
                                    if index < store.topSites.count - 1 { Palette.line.frame(height: 1).padding(.leading, 54) }
                                }
                            }
                        }
                        .kCard(radius: 20)
                    }
                    .arrives(3)
                }

                Button {
                    sheet = .customize
                } label: {
                    Label("Customize home", systemImage: "slider.horizontal.3")
                        .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { homeBackground }
    }

    @ViewBuilder
    private var homeBackground: some View {
        switch store.home.background {
        case .kairos:
            Color.clear
        case .colour:
            Color(hex: Palette.botSage).opacity(0.3 * (1 - store.home.dim)).ignoresSafeArea()
        case .picture:
            LinearGradient(colors: [Color(hex: Palette.botPowder), Color(hex: Palette.botSand)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.45 * (1 - store.home.dim))
                .ignoresSafeArea()
        }
    }

    private var tileHeight: CGFloat {
        switch store.home.tiles {
        case .small: 74
        case .medium: 92
        case .large: 112
        }
    }

    private func tile(_ site: SpeedSite) -> some View {
        Button {
            Haptics.tap()
            if editingDial { sheet = .editSite(site) } else { store.go(site.url) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Text(site.name)
                    .font(KFont.ui(store.home.tiles == .small ? 12.5 : 14.5, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.night)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: tileHeight, alignment: .bottomLeading)
            .background(Color(hex: site.colorHex), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if editingDial {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.night.opacity(0.7))
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityLabel(editingDial ? "Edit \(site.name)" : "Open \(site.name)")
        .contextMenu {
            Button("Open in a new tab", systemImage: "plus.square.on.square") { store.go(site.url, newTab: true) }
            Button("Rename", systemImage: "pencil") { sheet = .editSite(site) }
            Button("Change address", systemImage: "link") { sheet = .editSite(site) }
            Button("Refresh picture", systemImage: "arrow.clockwise") {
                chrome.say("The picture updates the next time you open the site.")
            }
            Button("Remove", systemImage: "trash", role: .destructive) {
                withAnimation(Motion.snappy) { store.removeSite(site.id) }
            }
        }
    }

    // MARK: Bottom bar

    private var suggestions: [(title: String, url: String)] {
        addressFocused && draft != tab.url ? store.suggestions(for: draft) : []
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, item in
                        Button {
                            addressFocused = false
                            store.go(item.url)
                        } label: {
                            CardRow(symbol: "clock.arrow.circlepath", title: item.title, detail: BrowseAddress.host(of: item.url), last: index == suggestions.count - 1, chevron: false)
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                    }
                }
                .kGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 4) {
                Button {
                    Haptics.tap()
                    if !tab.isBlank { sheet = .site }
                } label: {
                    Image(systemName: tab.isBlank ? "magnifyingglass" : (tab.secure ? "lock.fill" : "exclamationmark.triangle"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tab.isBlank ? Palette.inkFaint : (tab.secure ? Palette.success : Palette.danger))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(tab.isBlank)
                .accessibilityLabel(tab.secure ? "Site info, secure" : "Site info, not secure")

                TextField("Search \(store.engine.rawValue) or enter address", text: $draft)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .focused($addressFocused)
                    .submitLabel(.go)
                    .keyboardType(.webSearch)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { open(draft) {} }

                if tab.blocked > 0 && !addressFocused {
                    Button {
                        sheet = .site
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "shield.fill").font(.system(size: 10, weight: .bold))
                            Text("\(tab.blocked)").font(KFont.ui(12.5, .semibold, relativeTo: .caption)).monospacedDigit()
                        }
                        .foregroundStyle(Palette.danger)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(Palette.danger.opacity(0.14), in: Capsule())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(tab.blocked) ads and trackers blocked on this page")
                }

                if addressFocused {
                    iconButton("xmark.circle.fill", "Clear address") { draft = "" }
                } else if !tab.isBlank {
                    iconButton(store.loading ? "xmark" : "arrow.clockwise", store.loading ? "Stop loading" : "Reload") {
                        if store.loading { store.stopLoading() } else { store.reload() }
                    }
                    .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 52)
            .kGlass(Capsule())

            if !addressFocused {
                HStack(spacing: 0) {
                    barButton("chevron.left", "Back", enabled: !tab.back.isEmpty) { store.goBack() }
                    barButton("chevron.right", "Forward", enabled: !tab.forward.isEmpty) { store.goForward() }
                    barButton("house", "Home", enabled: true) { store.goHome() }
                    barButton("sparkles", "Ask Kairos about this page", enabled: !tab.isBlank) { sheet = .ask }
                    Button {
                        Haptics.tap()
                        sheet = .tabs
                    } label: {
                        Text("\(store.tabs.count)")
                            .font(KFont.ui(13, .semibold, relativeTo: .caption))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 24, height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.ink, lineWidth: 1.6))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Tabs, \(store.tabs.count) open")
                }
                .padding(.horizontal, 6)
                .kGlass(Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .animation(Motion.snappy, value: addressFocused)
        .animation(Motion.snappy, value: suggestions.count)
    }

    private func barButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? Palette.ink : Palette.inkFaint.opacity(0.5))
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func open(_ text: String, then done: () -> Void) {
        addressFocused = false
        if let problem = store.go(text) {
            if tab.isBlank {
                chrome.say(problem)
            } else {
                withAnimation(Motion.snappy) { store.editActive { $0.notice = problem } }
            }
        } else {
            done()
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetView(_ item: BrowseSheet) -> some View {
        switch item {
        case .tabs: BrowseTabsSheet()
        case .site: BrowseSiteSheet(host: tab.host, secure: tab.secure, blocked: tab.blocked) { switchSheet(.settings) }
        case .history: BrowseHistorySheet()
        case .downloads: BrowseDownloadsSheet()
        case .passwords: BrowsePasswordsSheet()
        case .ask: BrowseAskSheet(tab: tab)
        case .settings: BrowseSettingsSheet { switchSheet(.passwords) }
        case .customize: BrowseHomeSheet()
        case .botWork: BrowseBotWorkSheet()
        case .addSite: BrowseSiteForm(site: nil)
        case .editSite(let site): BrowseSiteForm(site: site)
        }
    }

    private func switchSheet(_ next: BrowseSheet) {
        sheet = nil
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            sheet = next
        }
    }
}

// MARK: - The page itself

nonisolated struct BrowseFind: Equatable, Sendable {
    var id: Int
    var text: String
    var backward: Bool
}

/// Shows the PC's page. On sample data it renders a small page written here; nothing loads from the network.
struct BrowsePageView: UIViewRepresentable {
    let html: String
    let zoom: Int
    let find: BrowseFind

    final class Coordinator {
        var html = ""
        var findID = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.isOpaque = false
        view.backgroundColor = .white
        view.scrollView.backgroundColor = .white
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if context.coordinator.html != html {
            context.coordinator.html = html
            view.loadHTMLString(html, baseURL: nil)
        }
        let scale = CGFloat(zoom) / 100
        if abs(view.pageZoom - scale) > 0.001 { view.pageZoom = scale }
        if context.coordinator.findID != find.id {
            context.coordinator.findID = find.id
            let encoded = (try? JSONEncoder().encode(find.text)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
            let script = find.text.isEmpty
                ? "window.getSelection().removeAllRanges();"
                : "window.find(\(encoded), false, \(find.backward ? "true" : "false"), true);"
            view.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

// MARK: - Words

nonisolated enum BrowseWords {
    static func devices(_ list: [String]) -> String {
        switch list.count {
        case 0: return "nothing"
        case 1: return list[0]
        default: return list.dropLast().joined(separator: ", ") + " and " + (list.last ?? "")
        }
    }

    static func matches(_ query: String, in text: String) -> Int {
        let q = query.lowercased()
        guard !q.isEmpty else { return 0 }
        return text.lowercased().components(separatedBy: q).count - 1
    }

    static let zoomSteps = [25, 33, 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300, 400, 500]

    static func zoomStep(_ value: Int, up: Bool) -> Int {
        if up { return zoomSteps.first { $0 > value } ?? 500 }
        return zoomSteps.last { $0 < value } ?? 25
    }
}
