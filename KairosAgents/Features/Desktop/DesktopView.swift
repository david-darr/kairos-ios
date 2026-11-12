import SwiftUI

/// Your PC from your pocket: its status, Forge sessions, Computer, Browse, local models and files.
struct DesktopView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 54, height: 54)
                        .background(Palette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your PC").font(KFont.ui(18, .semibold, relativeTo: .headline)).foregroundStyle(Palette.ink)
                        HStack(spacing: 7) {
                            PulsingDot(color: Palette.success, size: 7)
                            Text("Online · Kairos 2.3.0").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .kGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .arrives(0)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Forge sessions").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                    VStack(spacing: 0) {
                        ForEach(Array(SampleData.forgeSessions.enumerated()), id: \.element.id) { index, session in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                                    HStack(spacing: 6) {
                                        Text(session.project).foregroundStyle(Palette.inkFaint)
                                        Text("+\(session.added)").foregroundStyle(Palette.success)
                                        Text("-\(session.removed)").foregroundStyle(Palette.danger)
                                        Text("· \(session.note)").foregroundStyle(session.waiting ? Palette.goldText : Palette.inkFaint)
                                    }
                                    .font(KFont.ui(13.5, relativeTo: .footnote))
                                    .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if session.waiting { Circle().fill(Palette.gold).frame(width: 10, height: 10) }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 66)
                            .overlay(alignment: .bottom) {
                                if index < SampleData.forgeSessions.count - 1 { Palette.line.frame(height: 1).padding(.leading, 16) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .kCard(radius: 22)
                }
                .arrives(1)

                VStack(spacing: 0) {
                    ForEach(Array(SampleData.desktopAreas.enumerated()), id: \.element.id) { index, entry in
                        EntryRow(entry: entry).arrives(index + 2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
        .shrinksBar(chrome)
        .safeAreaInset(edge: .top, spacing: 0) {
            TabHeader(title: "Desktop") {
                GlassIconButton(symbol: "magnifyingglass", label: "Search") { router.sheet = .search }
            }
        }
        .kScreen(glowAt: UnitPoint(x: 0.9, y: 0.02))
    }
}
