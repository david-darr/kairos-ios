import SwiftUI

// MARK: - Ground

/// The app's background: the deep ground with one warm glow.
struct Ground: View {
    var glowAt: UnitPoint = UnitPoint(x: 0.88, y: -0.05)

    var body: some View {
        ZStack {
            Palette.ground
            RadialGradient(
                colors: [Palette.glow, Palette.glow.opacity(0)],
                center: glowAt,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass and surfaces

extension View {
    /// Real Liquid Glass with the warm Kairos wash. For chrome: bars, round buttons, pills, composers.
    func kGlass<S: Shape>(_ shape: S, tint: Color = Palette.glassTint, interactive: Bool = false) -> some View {
        glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
    }

    /// A quiet translucent card for things inside the content.
    func kCard(radius: CGFloat = 20, raised: Bool = false) -> some View {
        background(raised ? Palette.surfaceRaised : Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }

    /// Every screen: the ground behind it and no system bar on top.
    func kScreen(glowAt: UnitPoint = UnitPoint(x: 0.88, y: -0.05)) -> some View {
        environment(\.groundGlow, glowAt)
            .background { Ground(glowAt: glowAt) }
            .toolbar(.hidden, for: .navigationBar)
    }

    /// Sheets are warm frosted glass, not the system grey.
    func kSheet(_ detents: Set<PresentationDetent> = [.large]) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationBackground {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Palette.ground.opacity(0.8)
                    RadialGradient(colors: [Palette.glow.opacity(0.55), Palette.glow.opacity(0)], center: .top, startRadius: 0, endRadius: 420)
                }
            }
    }

    /// Rows and cards arrive one after another.
    func arrives(_ index: Int) -> some View { modifier(Arrive(index: index)) }
}

private struct Arrive: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(Motion.sheet.delay(Double(index) * 0.045)) { shown = true }
            }
    }
}

/// Buttons sink a little when pressed.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// A round glass button with one icon.
struct GlassIconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .kGlass(Circle(), interactive: true)
        .accessibilityLabel(label)
    }
}

/// The filled gold button for the one main action on a screen.
struct GoldButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(KFont.ui(17, .semibold))
                .foregroundStyle(Palette.onGold)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
        }
        .buttonStyle(PressStyle(scale: 0.97))
    }
}

struct QuietButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(KFont.ui(16, .medium))
                .foregroundStyle(Palette.inkDim)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Small pieces

/// A dot that sends out a soft ring while something is running.
struct PulsingDot: View {
    var color: Color
    var size: CGFloat = 7
    @State private var out = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .stroke(color.opacity(0.55), lineWidth: 1.5)
                    .scaleEffect(out ? 2.6 : 1)
                    .opacity(out ? 0 : 0.9)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { out = true }
            }
            .accessibilityHidden(true)
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(KFont.label)
            .tracking(1.4)
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small rounded tag: the model chip, the approval chip, a type chip.
struct Chip: View {
    let text: String
    var symbol: String? = nil
    var filled = true

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(text).font(KFont.ui(13, .medium, relativeTo: .footnote))
        }
        .foregroundStyle(filled ? Palette.ink : Palette.inkDim)
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .background(filled ? Palette.ink.opacity(0.12) : .clear, in: Capsule())
        .overlay(Capsule().strokeBorder(filled ? .clear : Palette.lineStrong, lineWidth: 1))
    }
}

/// A plain grouped row, like iOS Settings.
struct GroupRow: View {
    let title: String
    var symbol: String? = nil
    var value: String? = nil
    var last = false

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 26)
            }
            Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            if let value { Text(value).font(KFont.ui(15)).foregroundStyle(Palette.inkFaint).lineLimit(1) }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, symbol == nil ? 16 : 54) }
        }
    }
}

/// The big title row at the top of each tab, with its round buttons on the right.
struct TabHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(KFont.ui(32, .semibold, relativeTo: .largeTitle))
                .foregroundStyle(Palette.ink)
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background { HeaderFade() }
    }
}

extension EnvironmentValues {
    /// Where the screen's ground glow sits, so a header can continue it.
    @Entry var groundGlow: UnitPoint = UnitPoint(x: 0.88, y: -0.05)
}

/// What sits behind a floating header. It repeats the screen's own ground, glow included, so the
/// header looks like open ground while what scrolls under it fades away instead of running through
/// the title. No blur.
struct HeaderFade: View {
    @Environment(\.groundGlow) private var glowAt

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let screen = UIScreen.main.bounds.size
            ZStack {
                Palette.ground
                RadialGradient(
                    colors: [Palette.glow, Palette.glow.opacity(0)],
                    center: UnitPoint(
                        x: (glowAt.x * screen.width - frame.minX) / max(frame.width, 1),
                        y: (glowAt.y * screen.height - frame.minY) / max(frame.height, 1)),
                    startRadius: 0,
                    endRadius: 520
                )
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.74),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

/// The glass switch along the top of a tab (Files, Notes, Calendar ...).
/// It is only as wide as its items, and scrolls sideways when they do not fit.
struct GlassSwitch<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    @Namespace private var ns

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row.kGlass(Capsule())
            ScrollView(.horizontal) { row }
                .scrollIndicators(.hidden)
                .kGlass(Capsule())
        }
    }

    private var row: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { selection = item }
                } label: {
                    Text(title(item))
                        .font(KFont.ui(15, on ? .semibold : .regular, relativeTo: .subheadline))
                        .foregroundStyle(on ? Palette.ink : Palette.inkDim)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 16)
                        .frame(minHeight: 38)
                        .background {
                            if on { Capsule().fill(Palette.ink.opacity(0.15)).matchedGeometryEffect(id: "on", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
    }
}

/// A sheet that is exactly as tall as what it holds (up to the full screen, where it scrolls).
struct FittedSheet<Content: View>: View {
    var estimate: CGFloat = 520
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .kSheet([.height(height > 0 ? height : estimate)])
    }
}
