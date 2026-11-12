import SwiftUI

// Small building blocks shared by every Bots screen. They sit on top of the design system.

// MARK: - Pages

/// A pushed Bots page: a back button, a centred title, an optional trailing control, and scrolling content.
struct BotsPage<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    /// true on a screen that reads the paired desktop. Every other Bots page says, while paired,
    /// that it still shows sample data.
    var live = false
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, subtitle: String? = nil, live: Bool = false, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.live = live
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !live { BotsSampleNote() }
                content
            }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                VStack(spacing: 1) {
                    Text(title)
                        .font(KFont.ui(17, .semibold, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(KFont.ui(12.5, relativeTo: .caption))
                            .foregroundStyle(Palette.inkFaint)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 64)
                HStack {
                    GlassIconButton(symbol: "chevron.left", label: "Back") { dismiss() }
                    Spacer()
                    trailing
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .background { HeaderFade() }
        }
        .kScreen()
        .botsToast()
    }
}

extension BotsPage where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, live: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, live: live, trailing: { EmptyView() }, content: content)
    }
}

/// A titled group of rows in one card.
struct BotsSection<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionLabel(text: title).padding(.horizontal, 4) }
            VStack(spacing: 0) { content }
                .kCard(radius: 20)
            if let footer {
                Text(footer)
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A thin line between rows in a card.
struct RowLine: View {
    var inset: CGFloat = 16
    var body: some View { Palette.line.frame(height: 1).padding(.leading, inset) }
}

/// A row that leads somewhere: icon, title, optional detail, a value and a chevron.
struct NavRow: View {
    let title: String
    var symbol: String? = nil
    var detail: String? = nil
    var value: String? = nil
    var badge: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                if let detail {
                    Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if badge > 0 { CountBadge(count: badge) }
            if let value {
                Text(value).font(KFont.ui(15)).foregroundStyle(Palette.inkFaint).lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// A gold count, capped at 99+.
struct CountBadge: View {
    let count: Int
    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(KFont.ui(12, .semibold, relativeTo: .caption))
            .foregroundStyle(Palette.onGold)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(Palette.gold, in: Capsule())
            .contentTransition(.numericText())
            .accessibilityLabel("\(count) waiting")
    }
}

/// A row with a switch.
struct ToggleRow: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { value in
            Haptics.select()
            withAnimation(Motion.snappy) { isOn = value }
        })) {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    if let detail {
                        Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(Palette.gold)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
    }
}

/// A number with minus and plus buttons, each 44 points.
struct StepperRow: View {
    let title: String
    var detail: String? = nil
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 1
    var unit = ""

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                if let detail { Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint) }
            }
            Spacer(minLength: 4)
            stepButton("minus", "Less") { value = max(range.lowerBound, value - step) }
                .disabled(value <= range.lowerBound)
            Text("\(value)\(unit.isEmpty ? "" : " \(unit)")")
                .font(KFont.ui(16, .medium))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 54)
            stepButton("plus", "More") { value = min(range.upperBound, value + step) }
                .disabled(value >= range.upperBound)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.ink.opacity(0.08), in: Circle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel("\(label) \(title.lowercased())")
    }
}

/// A row that shows a choice and opens a menu of options.
struct MenuRow: View {
    let title: String
    var symbol: String? = nil
    var detail: String? = nil
    let options: [String]
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { selection = option }
                } label: {
                    if option == selection { Label(option, systemImage: "checkmark") } else { Text(option) }
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    if let detail { Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint) }
                }
                Spacer(minLength: 8)
                Text(selection).font(KFont.ui(15)).foregroundStyle(Palette.inkDim).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(title), \(selection)")
    }
}

/// A text field in its own card, with an optional character count.
struct FieldCard: View {
    let title: String
    @Binding var text: String
    var placeholder = ""
    var limit: Int? = nil
    var lines: ClosedRange<Int> = 1...1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: title)
                if let limit {
                    Text("\(text.count) / \(limit.formatted())")
                        .font(KFont.ui(12, relativeTo: .caption))
                        .foregroundStyle(text.count > limit ? Palette.danger : Palette.inkFaint)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 4)
            TextField(placeholder, text: $text, axis: lines.upperBound > 1 ? .vertical : .horizontal)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .lineLimit(lines)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48, alignment: .topLeading)
                .kCard(radius: 16)
        }
    }
}

// MARK: - Choices

/// An in-content segmented choice with a gold pill on the selected item.
struct GoldSegmented<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var disabled: (Item) -> Bool = { _ in false }
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { selection = item }
                } label: {
                    Text(title(item))
                        .font(KFont.ui(14.5, on ? .semibold : .regular, relativeTo: .subheadline))
                        .foregroundStyle(on ? Palette.onGold : (disabled(item) ? Palette.inkFaint.opacity(0.6) : Palette.inkDim))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if on { Capsule().fill(Palette.gold).matchedGeometryEffect(id: "pill", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(disabled(item))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .kCard(radius: 26)
    }
}

/// Chips that wrap onto more lines. One or many can be on.
struct ChipPicker<Item: Hashable>: View {
    let items: [Item]
    let isOn: (Item) -> Bool
    let title: (Item) -> String
    let tap: (Item) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = isOn(item)
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { tap(item) }
                } label: {
                    Text(title(item))
                        .font(KFont.ui(15, on ? .semibold : .regular, relativeTo: .subheadline))
                        .foregroundStyle(on ? Palette.onGold : Palette.ink)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Color.clear : Palette.line, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Lays children out in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(width, widest), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Buttons

/// A pill button for actions inside cards. Filled is gold, danger is red text.
struct PillButton: View {
    enum Look { case filled, plain, danger }
    let title: String
    var symbol: String? = nil
    var look: Look = .plain
    var wide = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(KFont.ui(15, .semibold, relativeTo: .subheadline)).lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: 44)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private var foreground: Color {
        switch look {
        case .filled: Palette.onGold
        case .plain: Palette.ink
        case .danger: Palette.danger
        }
    }

    private var background: AnyShapeStyle {
        switch look {
        case .filled: AnyShapeStyle(Palette.gold)
        case .plain: AnyShapeStyle(Palette.ink.opacity(0.1))
        case .danger: AnyShapeStyle(Palette.danger.opacity(0.12))
        }
    }
}

/// "Swipe up to confirm": for risky actions like giving a bot full access.
struct SwipeToConfirm: View {
    let title: String
    var symbol = "chevron.up"
    let action: () -> Void
    @State private var drag: CGFloat = 0
    @State private var done = false
    private let travel: CGFloat = 120

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Palette.gold.opacity(0.14 + 0.3 * Double(progress)))
                    .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.5), lineWidth: 1))
                    .frame(width: 76, height: travel + 76)
                Circle()
                    .fill(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: done ? "checkmark" : symbol)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Palette.onGold)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                    .padding(.bottom, 6)
                    .offset(y: -drag)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !done else { return }
                                drag = min(travel, max(0, -value.translation.height))
                            }
                            .onEnded { _ in
                                if drag > travel * 0.8 {
                                    withAnimation(Motion.bouncy) { drag = travel; done = true }
                                    Haptics.success()
                                    action()
                                } else {
                                    withAnimation(Motion.bouncy) { drag = 0 }
                                }
                            }
                    )
            }
            Text(done ? "Confirmed" : title)
                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            done = true
            action()
        }
    }

    private var progress: CGFloat { drag / travel }
}

// MARK: - Meters and states

/// A horizontal meter. Gold, then red near the top.
struct MeterBar: View {
    let fraction: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.1))
                Capsule()
                    .fill(fraction > 0.9 ? Palette.danger : (fraction > 0.7 ? Palette.goldDeep : Palette.gold))
                    .frame(width: max(height, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
        .accessibilityLabel("\(Int(fraction * 100)) percent")
    }
}

/// A plain empty state: one line and an optional action.
struct EmptyNote: View {
    let text: String
    var symbol = "tray"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Palette.inkFaint)
            Text(text)
                .font(KFont.ui(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
    }
}

/// A one-line note under a section, sometimes with a symbol.
struct HintLine: View {
    let text: String
    var symbol: String? = nil
    var color: Color = Palette.inkFaint

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
            Text(text).font(KFont.ui(14, relativeTo: .footnote)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small coloured word: Working, Done, Failed ...
struct StateTag: View {
    let text: String
    var color: Color = Palette.inkDim
    var pulsing = false

    var body: some View {
        HStack(spacing: 5) {
            if pulsing { PulsingDot(color: color, size: 6) } else { Circle().fill(color).frame(width: 6, height: 6) }
            Text(text).font(KFont.ui(13, .medium, relativeTo: .footnote))
        }
        .foregroundStyle(color)
    }
}

/// A time shown as a 44 point chip that opens a wheel to change it.
struct TimeChip: View {
    @Binding var hour: Int
    @Binding var minute: Int
    var label = "Time"
    @State private var open = false

    var body: some View {
        Button {
            Haptics.tap()
            open = true
        } label: {
            Text(clockText(hour, minute))
                .font(KFont.ui(16, .medium))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Palette.ink.opacity(0.08), in: Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(label), \(clockText(hour, minute))")
        .sheet(isPresented: $open) {
            FittedSheet(estimate: 360) {
                VStack(spacing: 12) {
                    Text(label).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink).padding(.top, 30)
                    DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                    GoldButton(title: "Done") { open = false }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                hour = parts.hour ?? hour
                minute = parts.minute ?? minute
            }
        )
    }
}

/// The sheet title used by Bots sheets, with room under the grab bar.
struct SheetTitle: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

/// A confirm sheet for anything that removes or stops something.
struct ConfirmSheet: View {
    let title: String
    let detail: String
    let confirm: String
    var danger = true
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 300) {
            VStack(spacing: 16) {
                SheetTitle(title: title, detail: detail)
                PillButton(title: confirm, look: danger ? .danger : .filled, wide: true) {
                    Haptics.thud()
                    action()
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

extension Bot {
    /// The status in plain words.
    var statusWord: String {
        switch status {
        case .online: "Ready"
        case .working: "Working"
        case .needsYou: "Waiting for you"
        case .offline: "Asleep"
        }
    }

    var statusColor: Color {
        switch status {
        case .online: Palette.success
        case .working: Palette.working
        case .needsYou: Palette.goldText
        case .offline: Palette.inkFaint
        }
    }
}
