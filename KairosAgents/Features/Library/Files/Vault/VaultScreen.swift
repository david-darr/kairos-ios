import SwiftUI
import UIKit

/// States the debug pictures open in.
enum VaultDebug: Hashable {
    case none, search, links, history, write, preview, peek, focus, menu, conflict, todayPrompt
}

/// The Vault's own navigation, shared by every screen inside the cover.
@Observable
final class VaultNav {
    var path: [VaultRoute] = []
    var debug: VaultDebug
    var close: () -> Void = {}
    /// Set when "Ask Kairos" should start a chat after the cover closes.
    var askAbout: String?

    init(path: [VaultRoute], debug: VaultDebug) {
        self.path = path
        self.debug = debug
    }

    func open(_ id: String) {
        VaultStore.shared.remember(id)
        path.append(.note(id))
    }

    func openFolder(_ folder: String) { path.append(.folder(folder)) }

    func showMap(_ focus: String?) {
        if case .map = path.last {
            path.removeLast()
        }
        path.append(.map(focus))
    }

    func home() { path.removeAll() }
}

/// The Vault: Home, folders, notes and the Map, in one full-screen place.
struct VaultScreen: View {
    @State private var nav: VaultNav
    @State private var toaster = FilesToaster()
    @State private var store = VaultStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome

    init(start: VaultStart = .home, debug: VaultDebug = .none, route: VaultRoute? = nil) {
        let store = VaultStore.shared
        store.followConnection()
        var path: [VaultRoute] = route.map { [$0] } ?? []
        var debug = debug
        switch start {
        case .home: break
        case .note(let id): path = [.note(id)]
        case .map: path = [.map(nil)]
        case .today:
            if store.isSample {
                store.createToday()
                path = [.note(store.todayID)]
            } else {
                // The desktop makes today's note; Home opens it once the vault is read.
                debug = .todayPrompt
            }
        }
        _nav = State(initialValue: VaultNav(path: path, debug: debug))
    }

    var body: some View {
        NavigationStack(path: $nav.path) {
            VaultHomeView()
                .navigationDestination(for: VaultRoute.self) { route in
                    switch route {
                    case .folder(let folder): VaultFolderView(folder: folder)
                    case .note(let id): VaultNoteView(noteID: id)
                    case .list(let filter): VaultListView(filter: filter)
                    case .map(let focus): VaultMapView(focus: focus)
                    }
                }
        }
        .filesToasts(toaster)
        .environment(nav)
        .task(id: VaultStore.connectionKey) {
            store.followConnection()
            await store.loadLiveIfNeeded()
        }
        .onChange(of: store.problem) {
            if let problem = store.problem {
                toaster.say(problem)
                store.problem = nil
            }
        }
        .onAppear {
            nav.close = {
                let ask = nav.askAbout
                dismiss()
                if let ask {
                    Task {
                        try? await Task.sleep(for: .seconds(0.45))
                        router.push(.newChat, on: .home)
                        chrome.say("New chat about \(ask)")
                    }
                }
            }
        }
    }
}

// MARK: - Home

struct VaultHomeView: View {
    @Environment(VaultNav.self) private var nav
    @Environment(FilesToaster.self) private var toaster
    @State private var store = VaultStore.shared
    @State private var query = ""
    @State private var textHits: [(note: VaultNote, snippet: String)] = []
    @State private var searching = false
    @State private var textProblem: String?
    @State private var searchTry = 0
    @State private var month = Date.now
    @State private var confirmReload = false
    @State private var indexPrompt: VaultIndexPrompt?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FilesSearchField(text: $query, prompt: "Search vault") { openFirst() }
                    .accessibilityLabel("Search vault notes")
                liveStatus
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    cards
                } else {
                    results
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            FilesHeader(title: "Vault", subtitle: "\(store.notes.count) notes · \(store.folders.count) folders · \(store.linkCount) links", backSymbol: "chevron.down", backLabel: "Close Vault", back: { nav.close() }) {
                GlassIconButton(symbol: "point.3.connected.trianglepath.dotted", label: "Map of links") { nav.showMap(nil) }
                Menu {
                    Button("Today's note", systemImage: "calendar.badge.plus") { openToday() }
                    Button("Reload the vault", systemImage: "arrow.clockwise") { confirmReload = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("Vault options")
            }
        }
        .kScreen(glowAt: UnitPoint(x: 0.5, y: -0.08))
        .confirmationDialog("Reload the vault?", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("Reload") {
                store.reload()
                toaster.say("Vault reloaded")
            }
        } message: {
            Text("This reads every note again from your desktop.")
        }
        .task(id: "\(searchTry)|\(query)") { await runTextSearch() }
        .onAppear {
            if nav.debug == .search {
                query = "price"
            } else if nav.debug == .todayPrompt {
                nav.debug = .none
                openToday()
            }
        }
    }

    /// Paired: one plain sentence while the vault is read, or what failed with a Try again.
    @ViewBuilder
    private var liveStatus: some View {
        if !store.isSample {
            switch store.liveLoad {
            case .idle, .loading:
                VaultLiveLine(text: "Reading your vault from your desktop.")
            case .failed(let why):
                VaultLiveLine(text: why) { Task { await store.loadLive() } }
            case .loaded:
                EmptyView()
            }
        }
    }

    // MARK: Cards

    @ViewBuilder
    private var cards: some View {
        todayCard.arrives(0)
        pinnedCard.arrives(1)
        foldersCard.arrives(2)
        monthCard.arrives(3)
        recentCard.arrives(4)
        attentionCard.arrives(5)
        propertiesCard.arrives(6)
    }

    private var todayCard: some View {
        let exists = store.note(store.todayID) != nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide)))
                        .font(KFont.display(30))
                        .foregroundStyle(Palette.ink)
                    Text(Date.now.formatted(.dateTime.month(.wide).day().year()))
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                }
                Spacer()
                Image(systemName: "sun.max")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.goldText)
            }
            if !exists && store.hasTemplate {
                Text("From Daily note, into \(store.dailyFolder)")
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
            }
            GoldButton(title: exists ? "Open today's note" : "Create today's note") { openToday() }
            if let prompt = indexPrompt, let suggestion = store.indexSuggestion(for: prompt.id) {
                indexPanel(suggestion: suggestion, expecting: prompt.edited)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .kCard(radius: 24, raised: true)
        .animation(Motion.snappy, value: indexPrompt?.id)
    }

    /// "Add today to the Daily notes index?" with the one line it would add.
    private func indexPanel(suggestion: (index: VaultNote, line: String), expecting edited: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add today to the \(suggestion.index.title) index?")
                .font(KFont.ui(15.5, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
            Text("+ " + suggestion.line)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Palette.success)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    indexPrompt = nil
                } label: {
                    Text("Not now")
                        .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Palette.ink.opacity(0.08), in: Capsule())
                }
                .buttonStyle(PressStyle())
                Button {
                    Haptics.success()
                    if store.isSample {
                        let added = store.addToIndex(store.todayID, expecting: edited)
                        toaster.say(added ? "Added to the index" : "The index changed since; nothing was added. Open it to add the line by hand.")
                    } else {
                        Task {
                            let added = await store.addToIndexLive(store.todayID)
                            toaster.say(added ? "Added to the index" : "The index was not changed. Open it to add the line by hand.")
                        }
                    }
                    indexPrompt = nil
                } label: {
                    Text("Add line")
                        .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.goldText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Palette.gold.opacity(0.16), in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(12)
        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pinnedCard: some View {
        FilesGroup(label: "Pinned · \(store.pins.count)") {
            if store.pins.isEmpty {
                Text("Pin a note from its header to keep it here, on every device.")
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kCard(radius: 20)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(store.pins.compactMap { store.note($0) }) { note in
                            Button { nav.open(note.id) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Palette.goldText)
                                    Text(note.title)
                                        .font(KFont.ui(16, .medium))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    Text(FilesDates.ago(note.edited))
                                        .font(KFont.ui(13, relativeTo: .footnote))
                                        .foregroundStyle(Palette.inkFaint)
                                }
                                .padding(14)
                                .frame(width: 150, height: 120, alignment: .topLeading)
                                .kCard(radius: 20, raised: true)
                            }
                            .buttonStyle(PressStyle())
                            .contextMenu {
                                Button("Unpin", systemImage: "pin.slash") { withAnimation(Motion.snappy) { store.togglePin(note.id) } }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
    }

    private var foldersCard: some View {
        FilesGroup(label: "Folders") {
            VStack(spacing: 0) {
                if !store.recent.isEmpty {
                    VaultTreeGroup(title: "Recent", symbol: "clock", ids: store.recent)
                }
                VaultTree(folder: "", depth: 0)
            }
            .kCard(radius: 20)
        }
    }

    private var monthCard: some View {
        FilesGroup(label: "Daily notes") {
            VaultMonthStrip(month: $month)
                .padding(14)
                .kCard(radius: 20)
        }
    }

    private var recentCard: some View {
        FilesGroup(label: "Recently changed") {
            VStack(spacing: 0) {
                let items = store.recentlyChanged
                ForEach(Array(items.enumerated()), id: \.element.id) { index, note in
                    Button { nav.open(note.id) } label: {
                        VaultNoteRow(note: note, detail: recentDetail(note), last: index == items.count - 1)
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                }
            }
            .kCard(radius: 20)
        }
    }

    private func recentDetail(_ note: VaultNote) -> String {
        let ago = FilesDates.ago(note.edited)
        if !store.isSample {
            guard let label = note.changeLabel, !label.isEmpty else { return ago }
            return "\(ago) · \(label)"
        }
        switch note.editedBy {
        case "you": return "\(ago) · by you"
        case "outside Kairos": return "\(ago) · outside Kairos"
        default: return "\(ago) · by \(note.editedBy)"
        }
    }

    private var attentionCard: some View {
        FilesGroup(label: "Needs attention") {
            HStack(spacing: 10) {
                attentionTile(count: store.orphans.count, title: "Need a link", symbol: "link.badge.plus", filter: .orphans)
                attentionTile(count: store.lackingProperties.count, title: "Missing properties", symbol: "tag", filter: .missingProperties)
            }
        }
    }

    private func attentionTile(count: Int, title: String, symbol: String, filter: VaultFilter) -> some View {
        Button {
            Haptics.tap()
            nav.path.append(.list(filter))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                Text("\(count)")
                    .font(KFont.ui(28, .semibold, relativeTo: .title))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text(title)
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 20)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(count) \(title). Show them")
    }

    private var propertiesCard: some View {
        FilesGroup(label: "Browse by property") {
            let groups = store.propertyValues
            if groups.isEmpty {
                Text("No notes have status, project or type properties yet.")
                    .font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).kCard(radius: 20)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.key.capitalized)
                                .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkFaint)
                            VaultFlow(spacing: 6) {
                                ForEach(Array(group.values.enumerated()), id: \.offset) { _, item in
                                    Button {
                                        Haptics.tap()
                                        nav.path.append(.list(.property(group.key, item.value)))
                                    } label: {
                                        HStack(spacing: 5) {
                                            Text(item.value).foregroundStyle(Palette.ink)
                                            Text("\(item.count)").foregroundStyle(Palette.inkFaint)
                                        }
                                        .font(KFont.ui(14, relativeTo: .footnote))
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 36)
                                        .background(Palette.ink.opacity(0.08), in: Capsule())
                                        .frame(minHeight: 44)
                                        .contentShape(Capsule())
                                    }
                                    .buttonStyle(PressStyle())
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(radius: 20)
            }
        }
    }

    // MARK: Search results

    private var results: some View {
        let names = store.nameMatches(query)
        return VStack(alignment: .leading, spacing: 16) {
            FilesGroup(label: "Names") {
                if names.isEmpty {
                    Text("No note or folder names match.")
                        .font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                        .padding(.horizontal, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(names.enumerated()), id: \.element.id) { index, hit in
                            hitRow(hit, last: index == names.count - 1)
                        }
                    }
                    .kCard(radius: 20)
                }
            }
            FilesGroup(label: "In note text") {
                if searching {
                    HStack(spacing: 8) {
                        ProgressView().tint(Palette.goldText)
                        Text("Searching note text...").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    }
                    .padding(.horizontal, 4)
                } else if let textProblem {
                    VaultLiveLine(text: textProblem) { searchTry += 1 }
                } else if textHits.isEmpty {
                    Text("No note text matches.")
                        .font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                        .padding(.horizontal, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(textHits.enumerated()), id: \.offset) { index, hit in
                            Button { nav.open(hit.note.id) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(hit.note.title).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                                    Text(highlighted(hit.snippet))
                                        .font(KFont.ui(14, relativeTo: .footnote))
                                        .foregroundStyle(Palette.inkDim)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if index < textHits.count - 1 { Palette.line.frame(height: 1).padding(.leading, 16) }
                                }
                            }
                            .buttonStyle(PressStyle(scale: 0.99))
                        }
                    }
                    .kCard(radius: 20)
                }
            }
        }
    }

    @ViewBuilder
    private func hitRow(_ hit: VaultHit, last: Bool) -> some View {
        switch hit {
        case .note(let id):
            if let note = store.note(id) {
                Button { nav.open(id) } label: {
                    VaultNoteRow(note: note, detail: note.folder.isEmpty ? "Vault" : note.folder, last: last)
                }
                .buttonStyle(PressStyle(scale: 0.99))
            }
        case .folder(let path):
            Button {
                Haptics.tap()
                var parts: [String] = []
                for part in path.split(separator: "/") {
                    parts.append(String(part))
                    store.expanded.insert(parts.joined(separator: "/"))
                }
                query = ""
            } label: {
                VaultFolderRow(name: store.folderName(path), detail: path, count: store.noteCount(in: path), last: last)
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .accessibilityHint("Shows this folder in the list")
        }
    }

    private func highlighted(_ snippet: String) -> AttributedString {
        var text = AttributedString(snippet)
        let q = query.trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: q, options: .caseInsensitive) {
            text[range].foregroundColor = Palette.goldText
            text[range].font = KFont.ui(14, .semibold, relativeTo: .footnote)
        }
        return text
    }

    private func runTextSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            textHits = []
            searching = false
            return
        }
        searching = true
        textProblem = nil
        try? await Task.sleep(for: .milliseconds(store.isSample ? 220 : 350))
        if Task.isCancelled { return }
        do {
            let hits = try await store.searchText(q)
            if Task.isCancelled { return }
            textHits = hits
        } catch {
            if Task.isCancelled { return }
            Connection.shared.note(error)
            textHits = []
            textProblem = "Note text could not be searched. " + error.plainWords
        }
        searching = false
    }

    private func openFirst() {
        if let first = store.nameMatches(query).first(where: { if case .note = $0 { true } else { false } }), case .note(let id) = first {
            nav.open(id)
        } else if let hit = textHits.first {
            nav.open(hit.note.id)
        }
    }

    private func openToday() {
        Haptics.tap()
        guard store.isSample else {
            Task {
                await store.loadLiveIfNeeded()
                let made = await store.makeTodayLive()
                if let problem = made.problem {
                    toaster.say(problem)
                    return
                }
                if made.created {
                    toaster.say("Today's note created")
                    if let suggestion = store.indexSuggestion(for: store.todayID) {
                        withAnimation(Motion.snappy) { indexPrompt = VaultIndexPrompt(id: store.todayID, edited: suggestion.index.edited) }
                        return
                    }
                }
                nav.open(store.todayID)
            }
            return
        }
        if store.note(store.todayID) == nil {
            store.createToday()
            toaster.say("Today's note created")
            if let suggestion = store.indexSuggestion(for: store.todayID) {
                withAnimation(Motion.snappy) { indexPrompt = VaultIndexPrompt(id: store.todayID, edited: suggestion.index.edited) }
                return
            }
        }
        nav.open(store.todayID)
    }
}

/// The folder-index question shown after today's note is created.
struct VaultIndexPrompt: Equatable {
    let id: String
    let edited: Date
}

// MARK: - Rows and the folder tree

struct VaultNoteRow: View {
    let note: VaultNote
    var detail: String? = nil
    var last = false
    var indent: CGFloat = 0
    @State private var store = VaultStore.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: note.isDaily ? "calendar" : "doc.text")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(note.title).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                    if note.isIndex { TypeBadge(text: "Index") }
                    if store.pins.contains(note.id) {
                        Image(systemName: "pin.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.goldText)
                            .accessibilityLabel("Pinned")
                    }
                }
                if let detail {
                    Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
        }
        .padding(.leading, 14 + indent)
        .padding(.trailing, 16)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 52 + indent) }
        }
    }
}

struct VaultFolderRow: View {
    let name: String
    var detail: String? = nil
    let count: Int
    var open = false
    var last = false
    var indent: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: open ? "folder.fill" : "folder")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                if let detail { Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1) }
            }
            Spacer(minLength: 0)
            Text("\(count)").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
                .rotationEffect(.degrees(open ? 90 : 0))
        }
        .padding(.leading, 14 + indent)
        .padding(.trailing, 16)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 52 + indent) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(open ? "Open" : "Closed")
    }
}

/// A collapsible group of notes at the top of the tree ("Recent").
struct VaultTreeGroup: View {
    let title: String
    let symbol: String
    let ids: [String]
    @Environment(VaultNav.self) private var nav
    @State private var store = VaultStore.shared
    @State private var open = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.select()
                withAnimation(Motion.snappy) { open.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.goldText).frame(width: 26)
                    Text(title).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(ids.count)").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 52) }
            }
            .buttonStyle(PressStyle(scale: 0.99))
            if open {
                ForEach(ids.compactMap { store.note($0) }) { note in
                    Button { nav.open(note.id) } label: { VaultNoteRow(note: note, indent: 20) }
                        .buttonStyle(PressStyle(scale: 0.99))
                }
            }
        }
    }
}

/// The folder tree, filled as folders open. Dated folders get month headings.
struct VaultTree: View {
    let folder: String
    let depth: Int
    @Environment(VaultNav.self) private var nav
    @State private var store = VaultStore.shared

    var body: some View {
        let children = store.children(of: folder)
        let indent = CGFloat(depth) * 18
        VStack(spacing: 0) {
            ForEach(children.folders, id: \.self) { sub in
                let open = store.expanded.contains(sub)
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) {
                        if open { store.expanded.remove(sub) } else { store.expanded.insert(sub) }
                    }
                } label: {
                    VaultFolderRow(name: store.folderName(sub), count: store.noteCount(in: sub), open: open, indent: indent)
                }
                .buttonStyle(PressStyle(scale: 0.99))
                .contextMenu {
                    Button("Open folder", systemImage: "folder") { nav.openFolder(sub) }
                    if let index = store.indexNote(of: sub) {
                        Button("Open index note", systemImage: "doc.text") { nav.open(index.id) }
                    }
                }
                if open {
                    VaultTree(folder: sub, depth: depth + 1)
                        .transition(.opacity)
                    if store.noteCount(in: sub) == 0 {
                        Text("Empty folder").font(KFont.ui(14)).foregroundStyle(Palette.inkFaint)
                            .padding(.leading, 52 + indent).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    }
                }
            }
            ForEach(Array(VaultMonths.group(children.notes).enumerated()), id: \.offset) { _, group in
                if let heading = group.heading {
                    Text(heading.uppercased())
                        .font(KFont.label).tracking(1.2)
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 52 + indent)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                }
                ForEach(group.notes) { note in
                    Button { nav.open(note.id) } label: { VaultNoteRow(note: note, indent: indent) }
                        .buttonStyle(PressStyle(scale: 0.99))
                        .contextMenu { VaultNoteMenu(note: note) }
                }
            }
        }
    }
}

/// Long-press actions on a note row, in place of a right-click menu.
struct VaultNoteMenu: View {
    let note: VaultNote
    @Environment(VaultNav.self) private var nav
    @State private var store = VaultStore.shared

    var body: some View {
        Button("Open", systemImage: "doc.text") { nav.open(note.id) }
        Button(store.pins.contains(note.id) ? "Unpin" : "Pin", systemImage: store.pins.contains(note.id) ? "pin.slash" : "pin") {
            withAnimation(Motion.snappy) { store.togglePin(note.id) }
        }
        Button("Show on map", systemImage: "point.3.connected.trianglepath.dotted") { nav.showMap(note.id) }
        Button("Copy wikilink", systemImage: "link") { UIPasteboard.general.string = note.wikilink }
        Button("Copy path", systemImage: "doc.on.doc") { UIPasteboard.general.string = note.id + ".md" }
    }
}

nonisolated enum VaultMonths {
    struct Group { var heading: String?; var notes: [VaultNote] }

    /// Daily notes split by month; other notes keep one group with no heading.
    static func group(_ notes: [VaultNote]) -> [Group] {
        let daily = notes.filter(\.isDaily)
        guard daily.count >= 3 else { return [Group(heading: nil, notes: notes)] }
        var groups: [Group] = []
        let others = notes.filter { !$0.isDaily }
        for note in daily {
            guard let date = VaultDates.dailyDate(note.title) else { continue }
            let heading = VaultDates.monthTitle(date)
            if groups.last?.heading == heading {
                groups[groups.count - 1].notes.append(note)
            } else {
                groups.append(Group(heading: heading, notes: [note]))
            }
        }
        if !others.isEmpty { groups.append(Group(heading: nil, notes: others)) }
        return groups
    }
}

// MARK: - Month strip

struct VaultMonthStrip: View {
    @Binding var month: Date
    @Environment(VaultNav.self) private var nav
    @State private var store = VaultStore.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let calendar = Calendar.current
        let days = store.dailyNotes(inMonthOf: month)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let weekday = calendar.component(.weekday, from: start)
        let lead = (weekday + 5) % 7
        let isThisMonth = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        let today = calendar.component(.day, from: .now)

        VStack(spacing: 10) {
            HStack {
                Text(VaultDates.monthTitle(month))
                    .font(KFont.ui(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Spacer()
                stepButton("chevron.left", label: "Previous month", by: -1)
                stepButton("chevron.right", label: "Next month", by: 1)
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(KFont.ui(12, .medium, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 38) }
                ForEach(1...count, id: \.self) { day in
                    dayCell(day, note: days[day], isToday: isThisMonth && day == today)
                }
            }
            Text(footer(days.count))
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func footer(_ count: Int) -> String {
        if count > 0 { return count == 1 ? "1 daily note this month" : "\(count) daily notes this month" }
        if let latest = store.latestDaily { return "Latest daily note: \(latest.title)" }
        return "No daily notes yet."
    }

    private func stepButton(_ symbol: String, label: String, by step: Int) -> some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) {
                month = Calendar.current.date(byAdding: .month, value: step, to: month) ?? month
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.inkDim)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func dayCell(_ day: Int, note: String?, isToday: Bool) -> some View {
        let label = Text("\(day)")
            .font(KFont.ui(14, note == nil ? .regular : .semibold, relativeTo: .footnote))
            .frame(maxWidth: .infinity, minHeight: 38)
        if let note {
            Button {
                Haptics.tap()
                nav.open(note)
            } label: {
                label
                    .foregroundStyle(Palette.onGold)
                    .background(Palette.gold.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Daily note, day \(day)")
        } else {
            label
                .foregroundStyle(isToday ? Palette.goldText : Palette.inkDim)
                .overlay {
                    if isToday { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.gold, lineWidth: 1.5) }
                }
        }
    }
}

/// Lays pills out in rows, wrapping to the next row when they do not fit.
struct VaultFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            row = max(row, size.height)
        }
        return CGSize(width: min(width, widest), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
