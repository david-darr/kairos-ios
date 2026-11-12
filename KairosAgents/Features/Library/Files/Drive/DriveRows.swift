import SwiftUI

/// A file's kind as a tinted rounded tile.
struct DriveFileIcon: View {
    let kind: DriveKind
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(kind.tint)
            .frame(width: size, height: size)
            .background(kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A round letter for an account or a sharing member.
struct DriveAvatar: View {
    let letter: String
    var size: CGFloat = 40
    var muted = false

    var body: some View {
        Text(letter)
            .font(KFont.ui(size * 0.42, .semibold))
            .foregroundStyle(muted ? Palette.ink : Palette.onGold)
            .frame(width: size, height: size)
            .background(muted ? AnyShapeStyle(Palette.ink.opacity(0.12)) : AnyShapeStyle(Palette.gold), in: Circle())
            .accessibilityHidden(true)
    }
}

/// A thin storage bar.
struct DriveStorageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.1))
                Capsule()
                    .fill(Palette.gold)
                    .frame(width: max(6, geometry.size.width * CGFloat(fraction)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// One file in the list layout.
struct DriveFileRow: View {
    let file: DriveFile
    var selecting = false
    var picked = false
    var last = false

    var body: some View {
        HStack(spacing: 12) {
            if selecting {
                CheckCircle(on: picked)
                    .transition(.scale.combined(with: .opacity))
            }
            DriveFileIcon(kind: file.kind)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(KFont.ui(16, .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if file.starred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.goldText)
                            .accessibilityLabel("Starred")
                    }
                }
                Text(file.meta)
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if !file.badge.isEmpty { TypeBadge(text: file.badge, tint: file.kind.tint) }
            if !selecting {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, selecting ? 106 : 70) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One file in the grid layout.
struct DriveFileCard: View {
    let file: DriveFile
    var selecting = false
    var picked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                DriveFileIcon(kind: file.kind, size: 40)
                Spacer(minLength: 4)
                if selecting {
                    CheckCircle(on: picked)
                } else if file.starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.goldText)
                        .accessibilityLabel("Starred")
                }
            }
            Text(file.name)
                .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                Text(DriveFormat.day(file.modified))
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !file.badge.isEmpty { TypeBadge(text: file.badge, tint: file.kind.tint) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 18, raised: picked)
        .overlay {
            if picked {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.gold, lineWidth: 1.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A recent file in the Quick access row.
struct DriveQuickTile: View {
    let file: DriveFile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DriveFileIcon(kind: file.kind, size: 34)
                Spacer(minLength: 4)
                TypeBadge(text: file.badge, tint: file.kind.tint)
            }
            Text(file.name)
                .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(DriveFormat.day(file.modified))
                .font(KFont.ui(12.5, relativeTo: .caption))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(12)
        .frame(width: 150, alignment: .leading)
        .kCard(radius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The account card at the top of Drive: who is signed in, storage, and whether it is connected.
struct DriveAccountCard: View {
    let account: DriveAccount

    var body: some View {
        HStack(spacing: 14) {
            DriveAvatar(letter: account.letter, size: 46, muted: account.broken)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Google Drive")
                        .font(KFont.ui(13, .medium, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                    Circle()
                        .fill(account.broken ? Palette.danger : Palette.success)
                        .frame(width: 7, height: 7)
                    Text(account.broken ? "Reconnect needed" : "Connected")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(account.broken ? Palette.danger : Palette.success)
                }
                Text(account.email)
                    .font(KFont.ui(16.5, .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if account.broken {
                    Text("Sign-in expired or revoked")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkDim)
                } else {
                    DriveStorageBar(fraction: account.fraction)
                        .padding(.top, 2)
                    Text(account.storage)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(14)
        .kCard(radius: 22, raised: true)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows your Google accounts")
    }
}

/// A small icon-and-word button used in toolbars inside the content.
struct DriveToolButton: View {
    let symbol: String
    let title: String
    var danger = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                Text(title).font(KFont.ui(12, relativeTo: .caption)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(danger ? Palette.danger : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// A light reading panel, the same in both looks, like a page.
struct DrivePaper<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(Palette.night)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }
}
