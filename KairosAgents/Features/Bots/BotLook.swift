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
    /// The shapes offered. A paired bot can only be stored in the desktop's three.
    var shapes: [MascotShape] = MascotShape.allCases

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
                    ForEach(shapes, id: \.self) { option in
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
    var live = BotsSettingsLive.shared

    var body: some View {
        if live.active {
            BotSetLookScreen(botID: botID)
        } else {
            sample
        }
    }

    @ViewBuilder private var sample: some View {
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

/// Settings > Look and name while paired: name, job and a look the desktop can store (its three shapes, the six
/// colours and the six accessories). A form over the bot record (BotSetForm): it remembers the desktop values and
/// revision it was filled from and sends only what the person changed since, with that revision. Kip stays locked.
private struct BotSetLookScreen: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared
    @State private var name = ""
    @State private var job = ""
    @State private var colorHex: UInt32 = Palette.botPowder
    @State private var shape: MascotShape = .round
    @State private var accessory: MascotAccessory = .none
    @State private var form: BotSetForm?
    @State private var saving = false

    private static let nameLimit = 100
    private static let jobLimit = 200

    var body: some View {
        let agent = live.record(botID)
        BotsPage("Look and name", live: true) {
            BotSetUnsureNote(botID: botID)
            BotsLoadNote(state: live.shown(live.recordLoad[botID])) {
                Task {
                    await live.loadRecord(botID)
                    sync()
                }
            }
            if let agent, agent.isFrontDesk {
                let bot = store.bot(botID)
                VStack(spacing: 14) {
                    BotFace(bot: bot, size: 150, blinks: true)
                    Text(bot.name).font(KFont.display(36)).foregroundStyle(Palette.ink)
                    HintLine(text: "Kip always looks like Kairos's own Kip. Its name and look cannot be changed, so you always know who answers first.", symbol: "lock")
                        .padding(14)
                        .kCard(radius: 18)
                }
                .frame(maxWidth: .infinity)
            } else if agent != nil, let form {
                let edited = form.edited(values())
                let cleanName = BotSetForm.name(name)
                let blank = cleanName.isEmpty
                // Counted as the desktop counts: code points, after it tidies the text.
                let nameTooLong = BotSetForm.length(cleanName) > Self.nameLimit
                let jobTooLong = edited.contains("role") && BotSetForm.length(BotSetForm.job(job)) > Self.jobLimit
                FieldCard(title: "Name", text: $name, placeholder: "e.g. Juniper", limit: Self.nameLimit)
                if blank {
                    HintLine(text: "A bot needs a name.", symbol: "exclamationmark.circle", color: Palette.danger)
                } else if nameTooLong {
                    HintLine(text: "A name is at most 100 characters on your desktop.", symbol: "exclamationmark.circle", color: Palette.danger)
                }
                FieldCard(title: "Job", text: $job, placeholder: "What is this bot for?", limit: Self.jobLimit)
                if jobTooLong {
                    HintLine(text: "A job is at most 200 characters on your desktop.", symbol: "exclamationmark.circle", color: Palette.danger)
                }
                MascotPicker(colorHex: $colorHex, shape: $shape, accessory: $accessory, shapes: BotAvatarRules.shapes)
                    .padding(16)
                    .kCard(radius: 22)
                let ready = !edited.isEmpty && !blank && !nameTooLong && !jobTooLong && !saving && !live.busy.contains(botID)
                HStack(spacing: 10) {
                    PillButton(title: "Shuffle", symbol: "shuffle", wide: true) {
                        withAnimation(Motion.bouncy) {
                            colorHex = BotLook.colors.randomElement()?.hex ?? Palette.botGold
                            shape = BotAvatarRules.shapes.randomElement() ?? .round
                            accessory = BotLook.accessories.randomElement() ?? .none
                        }
                    }
                    .disabled(saving)
                    PillButton(title: saving ? "Saving" : "Save look", symbol: "checkmark", look: .filled, wide: true) { save() }
                        .disabled(!ready)
                        .opacity(ready ? 1 : 0.5)
                }
                let clashed = form.clashed.intersection(edited)
                if !clashed.isEmpty {
                    HintLine(text: "Your desktop changed \(Self.list(clashed)) while you were editing. Your choice is kept here; saving puts it in place of your desktop's.", symbol: "exclamationmark.triangle", color: Palette.goldText)
                }
                if !edited.isEmpty {
                    HintLine(text: "Changes are not saved yet.", symbol: "circle.dotted")
                }
                HintLine(text: "Your desktop keeps three shapes: round, squircle and tall.", symbol: "info.circle")
            }
        }
        // Read each time the page appears and when the connection becomes ready.
        .task(id: BotsSettingsLive.connectionKey) {
            sync()
            await live.loadRecord(botID)
            sync()
        }
        .onChange(of: live.record(botID)) { sync() }
        .onChange(of: live.busy.contains(botID)) { sync() }
    }

    private static func list(_ fields: Set<String>) -> String {
        let words = ["name", "role", "avatar"].filter { fields.contains($0) }.map { BotSetWords.field($0) }
        return words.count > 1 ? words.dropLast().joined(separator: ", ") + " and " + (words.last ?? "") : (words.first ?? "")
    }

    /// The look as one value: shape, colour and accessory. A shape the desktop cannot store shows as round.
    private static func look(_ shape: MascotShape, _ color: UInt32, _ accessory: MascotAccessory) -> String {
        "\(shape.rawValue)|\(String(format: "#%06X", color))|\(accessory.rawValue)"
    }

    private static func shown(_ agent: AgentDTO) -> MascotShape {
        BotAvatarRules.shapes.contains(agent.mascotShape) ? agent.mascotShape : .round
    }

    /// The desktop's values, tidied the way the desktop tidies what it is sent.
    private static func values(_ agent: AgentDTO) -> [String: String] {
        ["name": BotSetForm.name(agent.name), "role": BotSetForm.job(agent.role),
         "avatar": look(shown(agent), agent.bodyColorHex, agent.mascotAccessory)]
    }

    private func values() -> [String: String] {
        ["name": BotSetForm.name(name), "role": BotSetForm.job(job), "avatar": Self.look(shape, colorHex, accessory)]
    }

    private func refill(_ key: String, from agent: AgentDTO) {
        switch key {
        case "name": name = agent.name ?? ""
        case "role": job = agent.role ?? ""
        case "avatar":
            colorHex = agent.bodyColorHex
            shape = Self.shown(agent)
            accessory = agent.mascotAccessory
        default: break
        }
    }

    /// Fill the form from the desktop, or bring an open one up to the newest read: untouched fields take the
    /// desktop's values, edited ones stay. Waits while a change is on its way.
    private func sync(acknowledge: Bool = false) {
        guard live.isCurrent, let agent = live.record(botID), !agent.isFrontDesk, !saving, !live.busy.contains(botID) else { return }
        let desktop = Self.values(agent)
        let revision = agent.revision ?? 0
        guard var next = form, next.account == BotsSettingsLive.accountKey else {
            for key in desktop.keys { refill(key, from: agent) }
            form = BotSetForm(account: BotsSettingsLive.accountKey, revision: revision, values: desktop)
            return
        }
        for key in next.rebase(form: values(), desktop: desktop, revision: revision, acknowledge: acknowledge) {
            refill(key, from: agent)
        }
        form = next
    }

    private func save() {
        guard let form, !saving, let agent = live.record(botID) else { return }
        let now = values()
        let edited = form.edited(now)
        guard !edited.isEmpty else { return }
        var changes: [String: Any] = [:]
        if edited.contains("name") { changes["name"] = now["name"] }
        if edited.contains("role") { changes["role"] = now["role"] }
        if edited.contains("avatar") {
            changes["avatar"] = [
                "version": 3,
                "character": "ajar",
                "shape": shape.rawValue,
                "color": String(format: "#%06X", colorHex),
                "acc": accessory.rawValue,
                // Not part of the form: the desktop's own, checked by the revision sent.
                "finish": agent.avatar?.finish ?? "flat",
            ] as [String: Any]
        }
        saving = true
        Task {
            let outcome = await live.patch(botID, changes, revision: form.revision, what: "the new look", done: "Look saved.")
            saving = false
            if case .changed = outcome {
                sync(acknowledge: true)
                store.say("This bot changed on your desktop, so nothing was saved. Your changes are kept here and the rest shows what your desktop has. Save again to use yours.")
            } else {
                sync()
                if !outcome.text.isEmpty { store.say(outcome.text) }
            }
            if outcome.isDone { Haptics.success() }
        }
    }
}
