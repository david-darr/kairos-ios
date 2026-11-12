import SwiftUI

/// The floating glass tab bar (bottom left), the gold action circle (bottom right),
/// and what floats above them: the live-work pill and short toasts.
/// Hold the bar and it grows into the Jump to panel.
struct BottomChrome: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @Namespace private var ns

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let toast = chrome.toast {
                ToastPill(text: toast)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let work = chrome.liveWork, !chrome.jumpOpen, !chrome.collapsed {
                LiveWorkPill(work: work)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            GlassEffectContainer(spacing: 16) {
                HStack(alignment: .bottom, spacing: 12) {
                    bar
                    if !chrome.jumpOpen {
                        Spacer(minLength: 0)
                        actionCircle
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .animation(Motion.bouncy, value: chrome.jumpOpen)
        .animation(Motion.snappy, value: chrome.collapsed)
        .animation(Motion.snappy, value: chrome.toast)
        .animation(Motion.snappy, value: router.pinned)
        .animation(Motion.snappy, value: router.tab)
    }

    // MARK: The bar

    private var bar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if chrome.jumpOpen {
                JumpPanel()
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomLeading)))
            }
            HStack(spacing: 2) {
                ForEach(AppTab.allCases) { tab in
                    if !chrome.collapsed || tab == router.tab { tabIcon(tab) }
                }
                if !chrome.collapsed {
                    ForEach(router.pinned) { area in pinnedIcon(area) }
                }
            }
        }
        .padding(6)
        .frame(maxWidth: chrome.jumpOpen ? .infinity : nil, alignment: .leading)
        .kGlass(RoundedRectangle(cornerRadius: chrome.jumpOpen ? 34 : 28, style: .continuous), interactive: !chrome.jumpOpen)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.38).onEnded { _ in
                guard !chrome.jumpOpen else { return }
                Haptics.thud()
                chrome.openJump()
            }
        )
        .dropDestination(for: String.self) { items, _ in
            guard let area = items.compactMap(JumpArea.init(rawValue:)).first else { return false }
            Haptics.success()
            router.pin(area)
            chrome.closeJump()
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main")
        .accessibilityAction(named: "Show every area") { chrome.openJump() }
    }

    private func tabIcon(_ tab: AppTab) -> some View {
        let selected = router.tab == tab
        return Image(systemName: tab.symbol)
            .symbolVariant(selected ? .fill : .none)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(selected ? Palette.ink : Palette.inkDim)
            .frame(width: 52, height: 44)
            .background {
                if selected && !chrome.collapsed {
                    Capsule().fill(Palette.ink.opacity(0.15)).matchedGeometryEffect(id: "selected", in: ns)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.select()
                if chrome.collapsed {
                    chrome.collapsed = false
                } else {
                    router.select(tab)
                    chrome.closeJump()
                }
            }
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func pinnedIcon(_ area: JumpArea) -> some View {
        Image(systemName: area.symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Palette.goldText)
            .frame(width: 48, height: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.select()
                chrome.closeJump()
                router.open(area)
            }
            .contextMenu {
                Button("Remove from the bar", systemImage: "minus.circle") { router.unpin(area) }
            }
            .transition(.scale(scale: 0.4).combined(with: .opacity))
            .accessibilityLabel(area.title)
            .accessibilityAddTraits(.isButton)
    }

    // MARK: The gold circle

    private var actionCircle: some View {
        Button {
            Haptics.tap()
            switch router.tab {
            case .home: router.push(.newChat, on: .home)
            case .make: chrome.say("Describe it in the box above")
            case .library: chrome.say("\(router.librarySection.addLabel): not built yet")
            case .desktop: chrome.say("New Forge session: not built yet")
            }
        } label: {
            Image(systemName: router.actionSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.onGold)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(PressStyle(scale: 0.88))
        .glassEffect(Glass.regular.tint(Palette.gold.opacity(0.5)).interactive(), in: Circle())
        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
        .accessibilityLabel(router.actionLabel)
    }
}

/// Every area in one grid. Tap to go there; drag one onto the bar to keep it there.
struct JumpPanel: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Jump to").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                Spacer()
                Button { chrome.closeJump() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.inkDim)
                        .frame(width: 32, height: 32)
                        .background(Palette.ink.opacity(0.1), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Close")
            }

            if !SampleData.addedTabs.isEmpty {
                SectionLabel(text: "Added tabs")
                ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(SampleData.addedTabs) { tab in
                        Button {
                            chrome.closeJump()
                            router.push(.page(tab.title))
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: tab.symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.goldText)
                                Text(tab.title).font(KFont.ui(14, .medium, relativeTo: .footnote)).foregroundStyle(Palette.ink).lineLimit(1).fixedSize()
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Palette.ink.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                }
                .scrollIndicators(.hidden)
            }

            SectionLabel(text: "Everything")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(JumpArea.allCases.enumerated()), id: \.element) { index, area in
                    Button {
                        Haptics.select()
                        chrome.closeJump()
                        router.open(area)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: area.symbol)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 52, height: 52)
                                .background(Palette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                            Text(area.title)
                                .font(KFont.ui(12.5, relativeTo: .caption))
                                .foregroundStyle(Palette.inkDim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.92))
                    .draggable(area.rawValue)
                    .contextMenu {
                        Button("Keep on the bar", systemImage: "pin") {
                            router.pin(area)
                            chrome.closeJump()
                        }
                    }
                    .arrives(index)
                }
            }

            Text("Drag one onto the bar to keep it there.")
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

/// What is running right now. Tap it to go to that work.
struct LiveWorkPill: View {
    let work: LiveWork
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            Haptics.tap()
            router.push(.bot(work.botID), on: .home)
        } label: {
            HStack(spacing: 9) {
                BotFace(bot: SampleData.bot(work.botID), size: 24)
                Text(work.text).font(KFont.ui(14, .medium, relativeTo: .footnote)).foregroundStyle(Palette.ink).lineLimit(1)
                if work.others > 0 {
                    Text("+\(work.others)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                PulsingDot(color: Palette.working)
                    .padding(.leading, 2)
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(height: 40)
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .kGlass(Capsule(), interactive: true)
        .accessibilityLabel("\(work.text). Open")
    }
}

struct ToastPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(KFont.ui(14, .medium, relativeTo: .footnote))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .kGlass(Capsule(), tint: Palette.glassTintStrong)
            .accessibilityAddTraits(.isStaticText)
    }
}
