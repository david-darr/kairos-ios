import SwiftUI

/// The bot look options: six pastels, eight shapes, five accessories (plus none).
enum BotLook {
    static let colors: [(name: String, hex: UInt32)] = [
        ("Gold", Palette.botGold), ("Powder", Palette.botPowder), ("Sand", Palette.botSand),
        ("Rose", Palette.botRose), ("Sage", Palette.botSage), ("Lilac", Palette.botLilac),
    ]

    static let accessories: [MascotAccessory] = [.none, .laurel, .spectacles, .quill, .rays, .scarf]

    static func name(_ shape: MascotShape) -> String {
        switch shape {
        case .round: "Round"
        case .squircle: "Squircle"
        case .tall: "Tall"
        case .dome: "Dome"
        case .wide: "Wide"
        case .hex: "Hex"
        case .scallop: "Scallop"
        case .ghost: "Ghost"
        }
    }

    static func name(_ accessory: MascotAccessory) -> String {
        switch accessory {
        case .none: "None"
        case .laurel: "Laurel"
        case .spectacles: "Spectacles"
        case .quill: "Quill"
        case .rays: "Rays"
        case .scarf: "Scarf"
        }
    }

    static func colorName(_ hex: UInt32) -> String {
        colors.first { $0.hex == hex }?.name ?? "Custom"
    }

    static func shuffled() -> (UInt32, MascotShape, MascotAccessory) {
        (colors.randomElement()?.hex ?? Palette.botGold,
         MascotShape.allCases.randomElement() ?? .round,
         accessories.randomElement() ?? .none)
    }
}

/// Pick a bot's colour, shape and accessory, with a live preview on top.
struct MascotPicker: View {
    @Binding var colorHex: UInt32
    @Binding var shape: MascotShape
    @Binding var accessory: MascotAccessory
    var previewSize: CGFloat = 150
    var showPreview = true

    private let shapeColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private let accessoryColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showPreview {
                HStack {
                    Spacer()
                    Mascot(shape: shape, colorHex: colorHex, accessory: accessory, size: previewSize, live: true)
                        .id("\(shape.rawValue)-\(accessory.rawValue)-\(colorHex)")
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    Spacer()
                }
                .frame(height: previewSize + 10)
                .animation(Motion.bouncy, value: shape)
                .animation(Motion.bouncy, value: accessory)
                .animation(Motion.bouncy, value: colorHex)
                .accessibilityElement()
                .accessibilityLabel("Preview: \(BotLook.colorName(colorHex)), \(BotLook.name(shape)), \(BotLook.name(accessory))")
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Body colour")
                HStack(spacing: 0) {
                    ForEach(BotLook.colors, id: \.hex) { colour in
                        let on = colour.hex == colorHex
                        Button {
                            Haptics.select()
                            colorHex = colour.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: colour.hex))
                                .frame(width: 36, height: 36)
                                .overlay(Circle().strokeBorder(Palette.ground, lineWidth: on ? 3 : 0))
                                .overlay(Circle().strokeBorder(on ? Palette.gold : Palette.line, lineWidth: on ? 2 : 1).padding(on ? -3 : 0))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.88))
                        .accessibilityLabel(colour.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Shape")
                LazyVGrid(columns: shapeColumns, spacing: 8) {
                    ForEach(MascotShape.allCases, id: \.self) { option in
                        tile(on: option == shape, label: BotLook.name(option)) {
                            shape = option
                        } content: {
                            Mascot(shape: option, colorHex: colorHex, size: 46, stage: Palette.surfaceSolid)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Accessory")
                LazyVGrid(columns: accessoryColumns, spacing: 8) {
                    ForEach(BotLook.accessories, id: \.self) { option in
                        tile(on: option == accessory, label: BotLook.name(option)) {
                            accessory = option
                        } content: {
                            Mascot(shape: shape, colorHex: colorHex, accessory: option, size: 46, stage: Palette.surfaceSolid)
                        }
                    }
                }
            }
        }
    }

    private func tile<Face: View>(on: Bool, label: String, pick: @escaping () -> Void, @ViewBuilder content: () -> Face) -> some View {
        Button {
            Haptics.select()
            pick()
        } label: {
            VStack(spacing: 4) {
                content()
                Text(label)
                    .font(KFont.ui(12.5, on ? .semibold : .regular, relativeTo: .caption))
                    .foregroundStyle(on ? Palette.ink : Palette.inkDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(on ? Palette.surfaceRaised : Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Palette.gold : Palette.line, lineWidth: on ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Settings > Look and name. Kip itself cannot be changed.
struct BotLookScreen: View {
    let botID: String
    let store = BotsStore.shared
    @State private var name = ""
    @State private var job = ""
    @State private var colorHex: UInt32 = Palette.botPowder
    @State private var shape: MascotShape = .round
    @State private var accessory: MascotAccessory = .none
    @State private var loaded = false

    var body: some View {
        let bot = store.bot(botID)
        BotsPage("Look and name") {
            if bot.isKip {
                VStack(spacing: 14) {
                    BotFace(bot: bot, size: 150, blinks: true)
                    Text(bot.name).font(KFont.display(36)).foregroundStyle(Palette.ink)
                    HintLine(text: "Kip always looks like Kairos's own Kip. Its name and look cannot be changed, so you always know who answers first.", symbol: "lock")
                        .padding(14)
                        .kCard(radius: 18)
                }
                .frame(maxWidth: .infinity)
            } else {
                FieldCard(title: "Name", text: $name, placeholder: "e.g. Juniper", limit: 100)
                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                    HintLine(text: "A bot needs a name.", symbol: "exclamationmark.circle", color: Palette.danger)
                }
                FieldCard(title: "Job", text: $job, placeholder: "What is this bot for?", limit: 200)
                MascotPicker(colorHex: $colorHex, shape: $shape, accessory: $accessory)
                    .padding(16)
                    .kCard(radius: 22)
                HStack(spacing: 10) {
                    PillButton(title: "Shuffle", symbol: "shuffle", wide: true) {
                        let next = BotLook.shuffled()
                        withAnimation(Motion.bouncy) {
                            colorHex = next.0
                            shape = next.1
                            accessory = next.2
                        }
                    }
                    PillButton(title: "Save look", symbol: "checkmark", look: .filled, wide: true) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !changed)
                        .opacity(changed ? 1 : 0.5)
                }
                if changed {
                    HintLine(text: "Changes are not saved yet.", symbol: "circle.dotted")
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = bot.name
            job = bot.role
            colorHex = bot.colorHex
            shape = bot.shape
            accessory = bot.accessory
        }
    }

    private var changed: Bool {
        let bot = store.bot(botID)
        return name != bot.name || job != bot.role || colorHex != bot.colorHex || shape != bot.shape || accessory != bot.accessory
    }

    private func save() {
        var bot = store.bot(botID)
        bot.name = name.trimmingCharacters(in: .whitespaces)
        bot.role = job
        bot.colorHex = colorHex
        bot.shape = shape
        bot.accessory = accessory
        store.botBinding(botID).wrappedValue = bot
        Haptics.success()
        store.say("Look saved")
    }
}
