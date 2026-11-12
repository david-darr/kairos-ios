import SwiftUI

// Rows and headers for the Chat documents screen.

/// A collapsible section header: a title, one line about it, a count and a chevron.
struct ChatDocsSectionHeader: View {
    let title: String
    let detail: String
    let count: Int
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { toggle() }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(KFont.ui(19, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(KFont.ui(14, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 24)
                    .background(Palette.ink.opacity(0.08), in: Capsule())
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
                    .rotationEffect(.degrees(open ? 0 : -90))
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .accessibilityLabel("\(title), \(count)")
        .accessibilityValue(open ? "Expanded" : "Collapsed")
        .accessibilityHint(open ? "Collapses the section" : "Expands the section")
    }
}

/// One Library document: its title, when it changed (or why it matched), and an arrow.
struct ChatDocsDocumentRow: View {
    let document: LibraryDocument
    let query: String
    let last: Bool
    let open: () -> Void

    private var detail: String {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return "Updated \(FilesDates.ago(document.updated))" }
        if document.title.localizedCaseInsensitiveContains(needle) { return "Title match" }
        return DocSnippet.make(document.body, query: needle) ?? "Updated \(FilesDates.ago(document.updated))"
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 40, height: 40)
                    .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .font(KFont.ui(16.5, .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { Palette.line.frame(height: 1).padding(.leading, 66) }
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .accessibilityHint("Opens the editor")
    }
}

/// One file sent to or made in a chat.
struct ChatDocsFileRow: View {
    let file: ChatDocsFile
    let last: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                TypeBadge(text: file.ext.isEmpty ? "File" : file.ext, tint: file.available ? Palette.goldText : Palette.inkFaint)
                    .frame(width: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                        .foregroundStyle(file.available ? Palette.ink : Palette.inkFaint)
                        .lineLimit(1)
                    Text(file.available ? "\(file.size) · \(file.origin.label)" : "No longer available")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if file.available {
                    Image(systemName: "eye")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { Palette.line.frame(height: 1).padding(.leading, 72) }
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .disabled(!file.available)
        .accessibilityHint(file.available ? "Opens the file" : "")
    }
}

/// One conversation's files, opening and closing in place.
struct ChatDocsGroupCard: View {
    let group: ChatDocsGroup
    let open: Bool
    let toggle: () -> Void
    let openFile: (ChatDocsFile) -> Void
    let openChat: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.select()
                withAnimation(Motion.snappy) { toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 26)
                    Text(group.title)
                        .font(KFont.ui(16, .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(NotesCopy.count(group.files.count, "file"))
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            .contextMenu {
                Button("Open chat", systemImage: "bubble.left.and.bubble.right", action: openChat)
            }

            if open {
                Palette.line.frame(height: 1)
                ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                    ChatDocsFileRow(file: file, last: index == group.files.count - 1) {
                        openFile(file)
                    }
                }
                .transition(.opacity)
            }
        }
        .kCard(radius: 20)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
