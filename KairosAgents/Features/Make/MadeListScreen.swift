import SwiftUI

/// Every made thing of one kind (videos, documents, decks, sheets, images), newest first,
/// with "Just made" marks. Files open in the document viewer; videos open in the editor.
struct MadeListScreen: View {
    let kind: MadeKind

    @Environment(MakeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var onlyNew = false
    @State private var viewer: MakeViewerStart?

    private var items: [MakeItem] {
        store.items(kind).filter { item in
            (!onlyNew || item.fresh) && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query) || item.source.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                        TextField("Search \(kind.plural.lowercased())", text: $query)
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
                .arrives(0)

                if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: kind.symbol).font(.system(size: 28, weight: .medium)).foregroundStyle(Palette.goldText)
                        Text(query.isEmpty ? "Nothing here yet." : "No \(kind.plural.lowercased()) match.")
                            .font(KFont.ui(16)).foregroundStyle(Palette.inkDim)
                        if !query.isEmpty || onlyNew {
                            PillButton(title: "Show all") {
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
                            if kind == .video {
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
            MakeHeader(title: kind.plural, subtitle: "\(store.items(kind).count) made", back: { dismiss() })
        }
        .kScreen()
        .sheet(item: $viewer) { start in
            DocumentViewer(documents: start.items.map(\.document), index: start.index)
                .kSheet()
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
}
