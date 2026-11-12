import SwiftUI

/// A list row with an icon tile, a title and one line of detail.
struct EntryRow: View {
    let entry: ListEntry

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 46, height: 46)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(entry.detail).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1).padding(.leading, 60) }
        .accessibilityElement(children: .combine)
    }
}
