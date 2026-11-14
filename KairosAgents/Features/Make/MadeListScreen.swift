import SwiftUI

/// Every made thing of one kind (videos, documents, decks, sheets, images), newest first,
/// with "Just made" marks. Files open in the document viewer; videos open in the editor.
/// Paired, it lists the desktop's own items of that kind (MakeHomeLive) and opens them by their desktop ids.
struct MadeListScreen: View {
    let kind: MadeKind

    @Environment(MakeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var onlyNew = false
    @State private var viewer: MakeViewerStart?
    @State private var liveFile: MakeHomeFileViewing?
    private let live = MakeHomeLive.shared

    /// Paired with a desktop: only the desktop's real items show, never a sample.
    private var paired: Bool { MakeHomeLive.paired }

    private var items: [MakeItem] {
        if paired {
            guard live.showing else { return [] }
            return live.items(kind).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
        }
        return store.items(kind).filter { item in
            (!onlyNew || item.fresh) && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query) || item.source.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                        TextField("Search \(title.lowercased())", text: $query)
                            .font(KFont.ui(16))
                            .foregroundStyle(Palette.ink)
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkFaint).frame(width: 32, height: 44)
                            }
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .kCard(radius: 23)

                    // The desktop has no "just made" mark, so the filter is only on the sample list.
                    if !paired {
                        Button {
                            Haptics.select()
                            withAnimation(Motion.snappy) { onlyNew.toggle() }
                        } label: {
                            Chip(text: "Just made", symbol: "sparkles", filled: onlyNew)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityAddTraits(onlyNew ? .isSelected : [])
                    }
                }
                .arrives(0)

                if paired {
                    liveLines
                }

                if items.isEmpty && (!paired || live.load == .loaded) {
                    VStack(spacing: 10) {
                        Image(systemName: kind.symbol).font(.system(size: 28, weight: .medium)).foregroundStyle(Palette.goldText)
                        Text(query.isEmpty ? "Nothing here yet." : "No \(title.lowercased()) match.")
                            .font(KFont.ui(16)).foregroundStyle(Palette.inkDim)
                        if !query.isEmpty || onlyNew {
                            MakePillButton(title: "Show all") {
                                query = ""
                                onlyNew = false
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Group {
                            if paired {
                                liveRow(item)
                            } else if kind == .video {
                                NavigationLink(value: MakeRoute.editor(item.id)) { row(item) }
                            } else {
                                Button {
                                    Haptics.tap()
                                    open(item)
                                } label: { row(item) }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        .arrives(index + 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            MakeHeader(title: title, subtitle: "\(paired ? (live.showing ? live.items(kind).count : 0) : store.items(kind).count) made", back: { dismiss() })
        }
        .kScreen()
        .sheet(item: $viewer) { start in
            DocumentViewer(documents: start.items.map(\.document), index: start.index)
                .kSheet()
        }
        .sheet(item: $liveFile) { start in
            DocsLiveViewer(files: start.files, index: start.index)
                .kSheet()
        }
        .task(id: MakeHomeLive.connectionKey) {
            live.followConnection()
            await live.loadLiveIfNeeded()
        }
    }

    private var title: String { paired ? MakeHomeLive.shelfTitle(kind) : kind.plural }

    @ViewBuilder
    private var liveLines: some View {
        if !live.showing || (live.load == .loading && live.items.isEmpty) || live.load == .idle {
            MakeHomeLine(text: "Reading what you made from your desktop.")
        } else if case .failed(let why) = live.load {
            MakeHomeLine(text: why, action: "Try again") { Task { await live.loadLive() } }
        }
        if kind == .video, let problem = live.videosProblem {
            MakeHomeLine(text: problem, action: "Try again") { Task { await live.loadLive() } }
        }
    }

    private func row(_ item: MakeItem) -> some View {
        HStack(spacing: 14) {
            MadeArt(item: item)
                .frame(width: 72, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    if item.fresh { JustMadeMark() }
                }
                Text("\(item.detail) · \(item.size)").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                Text("From \(item.source) · \(item.when)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 86) }
        .accessibilityElement(children: .combine)
    }

    private func open(_ item: MakeItem) {
        let list = items
        viewer = MakeViewerStart(items: list, index: list.firstIndex(of: item) ?? 0)
    }

    // MARK: Paired

    /// A desktop item: designs and slides open the design screen and videos the editor, both by the desktop's id;
    /// files open in the file viewer. An item the desktop gives no safe link for shows without one.
    @ViewBuilder
    private func liveRow(_ item: MakeItem) -> some View {
        switch live.opens[item.id] {
        case .some(.design(let id)):
            NavigationLink(value: MakeRoute.design(id)) { liveRowBody(item, linked: true) }
        case .some(.video(let id)):
            NavigationLink(value: MakeRoute.editor(id)) { liveRowBody(item, linked: true) }
        case .some(.file):
            Button {
                Haptics.tap()
                liveFile = live.fileViewing(item)
            } label: { liveRowBody(item, linked: true) }
        case .none:
            liveRowBody(item, linked: false)
        }
    }

    private func liveRowBody(_ item: MakeItem, linked: Bool) -> some View {
        HStack(spacing: 14) {
            MadeArt(item: item)
                .frame(width: 72, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(item.detail.isEmpty ? item.kind.title : item.detail)
                    .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                if !item.when.isEmpty {
                    Text(item.when).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if linked {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 86) }
        .accessibilityElement(children: .combine)
    }
}
