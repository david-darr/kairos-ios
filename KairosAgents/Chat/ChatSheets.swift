import SwiftUI
import UIKit

/// Everything a chat can do, from the + button: add photos and files, or start a kind of work.
struct ToolsSheet: View {
    nonisolated enum Action: Hashable, Sendable {
        case photos
        case files
        /// Put these words in the composer, ready to finish.
        case starter(String)
        case compact
        case summary
    }

    /// What the chat does with the choice. The sheet closes itself first.
    var onAction: (Action) -> Void = { _ in }
    /// Compact and Chat summary only make sense for a chat that has messages.
    var chatActions = false

    @Environment(\.dismiss) private var dismiss

    private var tools: [(symbol: String, title: String, detail: String, action: Action)] {
        var rows: [(symbol: String, title: String, detail: String, action: Action)] = [
            ("globe", "Browse the web", "Watch it work in a live card", .starter("Browse the web and ")),
            ("desktopcomputer", "Use my computer", "Click and type on your desktop", .starter("Use my computer to ")),
            ("paintpalette", "Design", "A page, a post or a screen, on a canvas", .starter("Design ")),
            ("doc.text", "Document", "A doc, deck or sheet you can export", .starter("Write a document about ")),
            ("clock", "Run in the background", "Keep going after you leave", .starter("In the background, ")),
            ("bolt", "Use a skill", "Saved ways of doing a job", .starter("Use a skill to ")),
        ]
        if chatActions {
            rows.append(("text.alignleft", "Chat summary", "What this chat has covered so far", .summary))
            rows.append(("arrow.down.right.and.arrow.up.left", "Compact this chat", "Summarise older turns. Nothing is deleted", .compact))
        }
        return rows
    }

    var body: some View {
        FittedSheet(estimate: 660) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    bigTile("photo.on.rectangle", "Photos", "From your library", .photos)
                    bigTile("folder", "Files", "From this iPhone", .files)
                }
                .padding(.horizontal, 18)
                .padding(.top, 34)

                VStack(spacing: 0) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                        Button { choose(tool.action) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: tool.symbol)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                    .frame(width: 40, height: 40)
                                    .background(Palette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tool.title).font(KFont.ui(16.5)).foregroundStyle(Palette.ink)
                                    Text(tool.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if index < tools.count - 1 { Palette.line.frame(height: 1).padding(.leading, 54) }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        .arrives(index)
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 20)
        }
    }

    private func bigTile(_ symbol: String, _ title: String, _ detail: String, _ action: Action) -> some View {
        Button { choose(action) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(Palette.goldText)
                Text(title).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                Text(detail).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .kCard(radius: 20, raised: true)
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .accessibilityLabel("\(title), \(detail)")
    }

    private func choose(_ action: Action) {
        Haptics.tap()
        dismiss()
        onAction(action)
    }
}

/// The file viewer: "n of N", Copy and Share, a details pill, the file large on a light panel,
/// thumbnails bottom left, and sideways swipes between files.
struct DocumentViewer: View {
    let documents: [ChatDocument]
    @State var index: Int
    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Text("\(index + 1) of \(documents.count)")
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    Spacer()
                    Button {
                        UIPasteboard.general.string = documents[index].name
                        Haptics.success()
                        withAnimation(Motion.snappy) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.4))
                            withAnimation(Motion.snappy) { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Copy")
                    ShareLink(item: documents[index].name) {
                        Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Share")
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.ink)
            }
            .padding(.top, 28)
            .padding(.horizontal, 12)

            HStack(spacing: 10) {
                Text(documents[index].label).font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(Palette.ink)
                ForEach(documents[index].details, id: \.self) { detail in
                    Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .kCard(radius: 14)
            .padding(.horizontal, 16)

            TabView(selection: $index) {
                ForEach(Array(documents.enumerated()), id: \.offset) { offset, document in
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0xF4F1EC))
                        DocumentArt(look: document.look)
                            .aspectRatio(document.look == .page ? 0.77 : 1.6, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                            .padding(document.look == .page ? 28 : 0)
                    }
                    .padding(.horizontal, 16)
                    .tag(offset)
                    .accessibilityLabel(document.name)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(Array(documents.enumerated()), id: \.offset) { offset, document in
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) { index = offset }
                    } label: {
                        DocumentArt(look: document.look)
                            .frame(width: 56, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(offset == index ? Palette.gold : Palette.line, lineWidth: offset == index ? 2 : 1))
                            .scaleEffect(offset == index ? 1.06 : 1)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Show \(document.name)")
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
        .animation(Motion.snappy, value: index)
    }
}
