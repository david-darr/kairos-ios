import SwiftUI

// MARK: - Make

/// One place for everything Kairos creates: describe it, pick a kind, and find what was made.
struct MakeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var prompt = ""
    @State private var kind = "Design"
    @FocusState private var typing: Bool

    private let kinds: [(String, String)] = [("Video", "film"), ("Design", "paintpalette"), ("Document", "doc.text"), ("Deck", "rectangle.on.rectangle"), ("Image", "photo")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Describe what to make...", text: $prompt, axis: .vertical)
                        .font(KFont.ui(17))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2...5)
                        .focused($typing)
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(kinds, id: \.0) { item in
                                Button {
                                    Haptics.select()
                                    withAnimation(Motion.snappy) { kind = item.0 }
                                } label: {
                                    Chip(text: item.0, symbol: item.1, filled: kind == item.0)
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityAddTraits(kind == item.0 ? .isSelected : [])
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
                .padding(16)
                .kGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .arrives(0)

                VStack(spacing: 10) {
                    sectionHead("Studio", trailing: "Content dashboard")
                    HStack(spacing: 12) {
                        Text("BS")
                            .font(KFont.ui(15, .semibold))
                            .foregroundStyle(Palette.night)
                            .frame(width: 46, height: 46)
                            .background(Color(hex: Palette.botRose), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Bike Shop Stories").font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                            Text("Today's video is waiting for your review").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: 0)
                        Circle().fill(Palette.gold).frame(width: 10, height: 10)
                    }
                    .padding(14)
                    .kCard(radius: 22)
                }
                .arrives(1)

                shelf("Designs", count: 11, items: SampleData.designs).arrives(2)
                shelf("Documents", count: 3, items: SampleData.madeDocuments).arrives(3)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .shrinksBar(chrome)
        .safeAreaInset(edge: .top, spacing: 0) {
            TabHeader(title: "Make") {
                GlassIconButton(symbol: "magnifyingglass", label: "Search") { router.sheet = .search }
            }
        }
        .kScreen(glowAt: UnitPoint(x: 0.15, y: -0.05))
    }

    private func sectionHead(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
            Spacer()
            HStack(spacing: 3) {
                Text(trailing)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
            .font(KFont.ui(14, relativeTo: .footnote))
            .foregroundStyle(Palette.inkFaint)
        }
    }

    private func shelf(_ title: String, count: Int, items: [MadeItem]) -> some View {
        VStack(spacing: 10) {
            sectionHead("\(title)  \(count)", trailing: "All")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            DocumentArt(look: item.look)
                                .frame(width: 168, height: 108)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    if item.fresh {
                                        Text("Just made")
                                            .font(KFont.ui(11.5, .semibold, relativeTo: .caption2))
                                            .foregroundStyle(Palette.onGold)
                                            .padding(.horizontal, 8)
                                            .frame(height: 22)
                                            .background(Palette.gold, in: Capsule())
                                            .padding(7)
                                    }
                                }
                            Text(item.title).font(KFont.ui(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink).lineLimit(1)
                            Text(item.when).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                        .padding(10)
                        .frame(width: 188, alignment: .leading)
                        .kCard(radius: 22)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

// MARK: - Library

/// Files (the Vault first), Notes, Calendar, Mail and Tasks behind one glass switch.
struct LibraryView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome

    var body: some View {
        @Bindable var router = router
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(SampleData.library(router.librarySection).enumerated()), id: \.element.id) { index, entry in
                    EntryRow(entry: entry)
                        .arrives(index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .id(router.librarySection)
            .transition(.opacity)
        }
        .scrollIndicators(.hidden)
        .shrinksBar(chrome)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                TabHeader(title: "Library") {
                    GlassIconButton(symbol: "magnifyingglass", label: "Search") { router.sheet = .search }
                }
                GlassSwitch(items: LibrarySection.allCases, selection: $router.librarySection) { $0.rawValue }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
        .kScreen(glowAt: UnitPoint(x: 0.5, y: -0.08))
        .animation(Motion.gentle, value: router.librarySection)
    }
}

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

// MARK: - Desktop

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
