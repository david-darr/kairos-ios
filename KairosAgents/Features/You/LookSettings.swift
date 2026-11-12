import PhotosUI
import SwiftUI
import UIKit

// MARK: - Sample state

nonisolated enum LookBackground: String, CaseIterable, Hashable, Sendable {
    case kairos, color, image, flow, glass, animated

    var title: String {
        switch self {
        case .kairos: "Kairos"
        case .color: "Color"
        case .image: "Image"
        case .flow: "Flow"
        case .glass: "Liquid glass"
        case .animated: "Animated"
        }
    }

    var line: String {
        switch self {
        case .kairos: "Parchment and bistre"
        case .color: "A clean canvas"
        case .image: "Your perspective"
        case .flow: "Color in motion"
        case .glass: "A see-through window"
        case .animated: "Art sets the colours"
        }
    }

    var symbol: String {
        switch self {
        case .kairos: "sparkles"
        case .color: "paintpalette"
        case .image: "photo"
        case .flow: "wind"
        case .glass: "drop"
        case .animated: "film"
        }
    }

    /// Effects and halftone scenes show only on these.
    var takesEffects: Bool { self == .kairos || self == .color }
}

nonisolated enum LookEffect: String, CaseIterable, Hashable, Sendable {
    case dithered, halftone, ascii, numbers, binary
    var title: String {
        switch self {
        case .dithered: "Dithered"
        case .halftone: "Halftone dots"
        case .ascii: "ASCII"
        case .numbers: "Numbers"
        case .binary: "Binary"
        }
    }
}

nonisolated enum KipStyle: String, CaseIterable, Hashable, Sendable {
    case flat, halftone, pixel, hidden
    var title: String { rawValue.capitalized }
}

nonisolated enum LookAppIcon: String, CaseIterable, Hashable, Sendable {
    case kairos, night, parchment, gold
    var title: String { rawValue.capitalized }
    /// The alternate icon's asset name; nil is the main icon.
    var assetName: String? { self == .kairos ? nil : "AppIcon-\(title)" }
}

nonisolated struct LookArtGroup: Identifiable, Sendable {
    let category: String
    let pieces: [String]
    var id: String { category }
}

/// The look, on this phone. The desktop's own look is set on the desktop; these mirror its choices.
@Observable
final class LookSample {
    static let shared = LookSample()

    static let swatches: [(name: String, hex: UInt32)] = [
        ("Parchment", 0xF3EADB), ("Linen", 0xEDE6DA), ("Stone", 0xC9C3B8), ("Clay", 0xB9826A), ("Plum", 0x4A3247),
        ("Ocean", 0x1F3A4D), ("Forest", 0x24382B), ("Graphite", 0x2B2B2E), ("Espresso", 0x2A1E17),
    ]
    static let wallpapers: [(name: String, colors: [UInt32])] = [
        ("Lagoon", [0x1F6F78, 0x6FB3B8, 0xE3D3A8]), ("Dusk", [0x3A2A52, 0xB0607A, 0xF0B27A]), ("Parchment", [0xF3EADB, 0xE2C99A, 0xB8893B]),
    ]
    static let artPieces: [LookArtGroup] = [
        LookArtGroup(category: "Landscapes", pieces: ["Aurora cabin snowfall", "Desert night drive", "Harbour at dawn"]),
        LookArtGroup(category: "Cosmos", pieces: ["Slow orbit", "Comet garden"]),
        LookArtGroup(category: "Retro computing", pieces: ["Green screen rain", "Boot sequence"]),
        LookArtGroup(category: "Weather and wild", pieces: ["Paper boats in rain", "Field of fireflies"]),
    ]

    var background: LookBackground = .kairos
    var baseName = "Espresso"
    var baseColor = Color(hex: 0x2A1E17)
    var imageData: Data?
    var imageTint = 0.35
    var distortion = 0.4
    var swirl = 0.3
    var grainMixer = 0.2
    var grainOverlay = 0.15
    var animateFlow = true
    var wallpaper = "Lagoon"
    var glass = 0.6
    var dither = 0.25
    var artPiece = "Aurora cabin snowfall"
    var artLook = "As made"
    var artPanels = 0.7
    var animateArt = true
    var halftone = true
    var scenes: [String: Bool] = ["Home": false, "New chat": false, "Conversation": true]
    var effect: LookEffect = .halftone
    var density = 8.0
    var effectTint = "Theme accent"
    var animateEffect = true
    var kip: KipStyle = .flat
    var chatStyle = "Standard"
    var chatMessages = "Plain"
    var icon: LookAppIcon = .kairos

    var image: UIImage? { imageData.flatMap { UIImage(data: $0) } }

    func reset() {
        background = .kairos
        baseName = "Espresso"
        baseColor = Color(hex: 0x2A1E17)
        imageData = nil
        imageTint = 0.35
        distortion = 0.4
        swirl = 0.3
        grainMixer = 0.2
        grainOverlay = 0.15
        animateFlow = true
        wallpaper = "Lagoon"
        glass = 0.6
        dither = 0.25
        artPiece = "Aurora cabin snowfall"
        artLook = "As made"
        artPanels = 0.7
        animateArt = true
        halftone = true
        scenes = ["Home": false, "New chat": false, "Conversation": false]
        effect = .halftone
        density = 8
        effectTint = "Theme accent"
        animateEffect = true
        kip = .flat
        chatStyle = "Standard"
        chatMessages = "Plain"
    }
}

// MARK: - Appearance

struct LookScreen: View {
    var start: LookBackground? = nil
    @Environment(AppModel.self) private var app
    @Bindable private var look = LookSample.shared
    @State private var confirmReset = false
    @State private var photo: PhotosPickerItem?
    @State private var artQuery = ""

    var body: some View {
        SettingsPage("Appearance", subtitle: "The look on this phone, and how your backgrounds and Kip look.") {
            Button { confirmReset = true } label: {
                Text("Reset").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16).frame(height: 44)
            }
            .buttonStyle(PressStyle())
            .kGlass(Capsule(), interactive: true)
        } content: {
            LookPreview()
                .arrives(0)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "The look").padding(.leading, 6)
                GlassSwitch(items: AppLook.allCases, selection: Binding(get: { app.appearance }, set: { app.setAppearance($0) })) { $0.title }
                Text("Night is deep brown with cream ink. Light is parchment with bistre ink.")
                    .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).padding(.horizontal, 8)
            }

            backgroundPicker
            styleOptions

            if look.background.takesEffects {
                effectGroup
                scenesGroup
            }

            kipGroup

            SettingsGroup("Chats", footer: "These set how chats look on your desktop. The phone always uses bubbles.") {
                PickRow(title: "Chat style", detail: "Terminal shows monospace prompt lines", selection: $look.chatStyle, options: ["Standard", "Terminal"]) { $0 }
                PickRow(title: "Chat messages", detail: "Plain sits on the backdrop", selection: $look.chatMessages, options: ["Plain", "Cards"]) { $0 }
            }

            iconGroup

            NoteText(text: "The usage notch floats at the edge of the Windows desktop app. Turn it on there, in Appearance.", symbol: "info.circle")
        }
        .confirmationDialog("Reset appearance?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                withAnimation(Motion.sheet) { look.reset() }
                YouStore.shared.say("Appearance reset")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your background picture, animation and scene pictures, and puts every choice back.")
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    withAnimation(Motion.snappy) {
                        look.imageData = data
                        look.background = .image
                    }
                    YouStore.shared.say("Picture saved on this phone")
                }
            }
        }
        .onAppear { if let start { look.background = start } }
    }

    // MARK: Background

    private var backgroundPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Background").padding(.leading, 6)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(LookBackground.allCases, id: \.self) { style in
                    styleCard(style)
                }
            }
        }
    }

    private func styleCard(_ style: LookBackground) -> some View {
        let on = look.background == style
        return Button {
            Haptics.select()
            withAnimation(Motion.snappy) { look.background = style }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: style.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(on ? Palette.onGold : Palette.goldText)
                    .frame(width: 34, height: 34)
                    .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(style.title).font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(style.line).font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(minHeight: 60)
            .kCard(radius: 18, raised: on)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Palette.gold : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private var styleOptions: some View {
        switch look.background {
        case .kairos:
            EmptyView()
        case .color:
            baseColourGroup
        case .flow:
            baseColourGroup
            SettingsGroup("Flow", footer: "Motion stops when Reduce Motion is on.") {
                SliderRow(title: "Distortion", value: $look.distortion) { percent($0) }
                SliderRow(title: "Swirl", value: $look.swirl) { percent($0) }
                SliderRow(title: "Grain mixer", value: $look.grainMixer) { percent($0) }
                SliderRow(title: "Grain overlay", value: $look.grainOverlay) { percent($0) }
                ToggleRow(title: "Animate background", isOn: $look.animateFlow)
            }
        case .image:
            imageGroup
        case .glass:
            glassGroup
        case .animated:
            animatedOptions
        }
    }

    private var baseColourGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Base colour").padding(.leading, 6)
            VStack(spacing: 0) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 12) {
                    ForEach(LookSample.swatches, id: \.name) { swatch in
                        swatchButton(swatch.name, hex: swatch.hex)
                    }
                }
                .padding(14)
                Palette.line.frame(height: 1).padding(.leading, 16)
                ColorPicker(selection: Binding(get: { look.baseColor }, set: { color in
                    look.baseColor = color
                    look.baseName = "Custom"
                }), supportsOpacity: false) {
                    RowLabel(title: "Your own colour", detail: look.baseName == "Custom" ? hex(look.baseColor) : "Your sidebar follows in a slightly darker shade")
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
            }
            .kCard(radius: 22)
        }
    }

    private func swatchButton(_ name: String, hex value: UInt32) -> some View {
        let on = look.baseName == name
        return Button {
            Haptics.select()
            withAnimation(Motion.snappy) {
                look.baseName = name
                look.baseColor = Color(hex: value)
            }
        } label: {
            VStack(spacing: 5) {
                Circle().fill(Color(hex: value))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(Palette.lineStrong, lineWidth: 1))
                    .overlay(Circle().strokeBorder(Palette.gold, lineWidth: on ? 3 : 0).padding(-4))
                Text(name).font(KFont.ui(11.5, relativeTo: .caption2)).foregroundStyle(Palette.inkDim).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(minHeight: 60)
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var imageGroup: some View {
        SettingsGroup("Your picture", footer: "PNG, JPEG or HEIC. It stays on this phone.") {
            PhotosPicker(selection: $photo, matching: .images) {
                RowLabel(title: look.image == nil ? "Choose a picture" : "Replace picture", symbol: "photo")
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.985))
            if look.image != nil {
                SliderRow(title: "Tint", value: $look.imageTint) { percent($0) }
                ActionRow(title: "Remove picture", symbol: "trash", tone: .danger) {
                    withAnimation(Motion.snappy) {
                        look.imageData = nil
                        look.background = .color
                    }
                    YouStore.shared.say("Picture removed. Color is on now.")
                }
            } else {
                NoteText(text: "Choose a picture to finish your background.")
                    .padding(.vertical, 12)
            }
        }
    }

    private var glassGroup: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Wallpaper").padding(.leading, 6)
                HStack(spacing: 10) {
                    ForEach(LookSample.wallpapers, id: \.name) { paper in
                        wallpaperButton(paper.name, colors: paper.colors)
                    }
                }
            }
            SettingsGroup(footer: "Seeing through to the desktop itself is a Windows desktop setting.") {
                SliderRow(title: "Glass", value: $look.glass) { percent($0) }
                SliderRow(title: "Dither", value: $look.dither) { percent($0) }
            }
        }
    }

    private func wallpaperButton(_ name: String, colors: [UInt32]) -> some View {
        let on = look.wallpaper == name
        return Button {
            Haptics.select()
            withAnimation(Motion.snappy) { look.wallpaper = name }
        } label: {
            VStack(spacing: 6) {
                LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Palette.gold : Palette.line, lineWidth: on ? 2.5 : 1))
                Text(name).font(KFont.ui(13, on ? .semibold : .regular, relativeTo: .footnote)).foregroundStyle(Palette.ink)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var filteredArt: [LookArtGroup] {
        let needle = artQuery.lowercased()
        return LookSample.artPieces.compactMap { group in
            let pieces = group.pieces.filter { needle.isEmpty || $0.lowercased().contains(needle) }
            return pieces.isEmpty ? nil : LookArtGroup(category: group.category, pieces: pieces)
        }
    }

    private var animatedOptions: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Art").padding(.leading, 6)
                SearchField(prompt: "Search pieces", text: $artQuery)
                VStack(spacing: 0) {
                    if filteredArt.isEmpty {
                        EmptyRow(text: "No piece matches \"\(artQuery)\".")
                    }
                    ForEach(filteredArt) { group in
                        Text(group.category.uppercased()).font(KFont.label).tracking(1.2).foregroundStyle(Palette.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                        ForEach(group.pieces, id: \.self) { piece in
                            artRow(piece)
                        }
                    }
                }
                .padding(.bottom, 6)
                .kCard(radius: 22)
            }
            SettingsGroup("How it plays", footer: "Art from ASCII Magic (MIT). Reduce Motion shows the first frame.") {
                PickRow(title: "Look", selection: $look.artLook, options: ["As made", "Halftone dots", "ASCII", "Dithered", "Blocks"]) { $0 }
                SliderRow(title: "Show art through panels", value: $look.artPanels) { percent($0) }
                ToggleRow(title: "Animate art", isOn: $look.animateArt)
            }
        }
    }

    private func artRow(_ piece: String) -> some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { look.artPiece = piece }
        } label: {
            HStack {
                Text(piece).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Spacer()
                if look.artPiece == piece {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.goldText)
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 46).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .accessibilityAddTraits(look.artPiece == piece ? .isSelected : [])
    }

    // MARK: Effects, scenes, Kip, icon

    private var effectGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Background effect").padding(.leading, 6)
            ChipPicker(items: LookEffect.allCases, selection: $look.effect) { $0.title }
            SettingsGroup {
                StepperRow(title: "Density", detail: "Cell size in points", value: Binding(get: { Int(look.density) }, set: { look.density = Double($0) }), range: 3...24)
                PickRow(title: "Tint", selection: $look.effectTint, options: look.effect == .dithered ? ["Original palette", "Theme accent", "Picture colours"] : ["Theme accent", "Picture colours"]) { $0 }
                ToggleRow(title: "Animate effect", isOn: $look.animateEffect)
            }
        }
    }

    private var scenesGroup: some View {
        SettingsGroup("Halftone scenes", footer: "Dotted pictures behind Home and chats. Your own pictures stay on this phone.") {
            ToggleRow(title: "Halftone backgrounds", isOn: $look.halftone)
            if look.halftone {
                ForEach(["Home", "New chat", "Conversation"], id: \.self) { scene in
                    sceneRow(scene)
                }
            }
        }
    }

    private func sceneRow(_ scene: String) -> some View {
        let custom = look.scenes[scene] ?? false
        return HStack(spacing: 12) {
            HalftoneThumb(seed: scene.count, custom: custom)
                .frame(width: 56, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            RowLabel(title: scene, detail: custom ? "Your picture" : "Kairos default")
            PillButton(title: "Replace") {
                withAnimation(Motion.snappy) { look.scenes[scene] = true }
                YouStore.shared.say("\(scene) scene replaced")
            }
            if custom {
                PillButton(title: "Reset") {
                    withAnimation(Motion.snappy) { look.scenes[scene] = false }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var kipGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Kip's style").padding(.leading, 6)
            HStack(spacing: 6) {
                ForEach(KipStyle.allCases, id: \.self) { style in
                    kipButton(style)
                }
            }
            .padding(12)
            .kCard(radius: 22)
            Text("Kip shows on Home, in a chat while it works, on empty pages and in calls. Hidden shows plain markers. Bots keep their own faces.")
                .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).padding(.horizontal, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func kipButton(_ style: KipStyle) -> some View {
        let on = look.kip == style
        return Button {
            Haptics.select()
            withAnimation(Motion.bouncy) { look.kip = style }
        } label: {
            VStack(spacing: 6) {
                KipPreview(style: style, size: 50)
                    .frame(width: 66, height: 66)
                    .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Palette.gold : Color.clear, lineWidth: 2))
                Text(style.title).font(KFont.ui(13, on ? .semibold : .regular, relativeTo: .footnote)).foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Kip \(style.title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var iconGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "App icon").padding(.leading, 6)
            HStack(spacing: 6) {
                ForEach(LookAppIcon.allCases, id: \.self) { icon in
                    iconButton(icon)
                }
            }
            .padding(14)
            .kCard(radius: 22)
        }
    }

    private func iconButton(_ icon: LookAppIcon) -> some View {
        let on = look.icon == icon
        return Button { choose(icon) } label: {
            VStack(spacing: 8) {
                AppIconPreview(icon: icon)
                    .frame(width: 62, height: 62)
                    .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Palette.gold, lineWidth: on ? 2.5 : 0).padding(-4))
                Text(icon.title).font(KFont.ui(13, on ? .semibold : .regular, relativeTo: .footnote)).foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .accessibilityLabel("\(icon.title) icon")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func choose(_ icon: LookAppIcon) {
        Haptics.select()
        withAnimation(Motion.snappy) { look.icon = icon }
        guard UIApplication.shared.supportsAlternateIcons else {
            YouStore.shared.say("This icon arrives in a later build.")
            return
        }
        UIApplication.shared.setAlternateIconName(icon.assetName) { error in
            let failed = error != nil
            Task { @MainActor in
                YouStore.shared.say(failed ? "This icon arrives in a later build." : "Icon changed")
            }
        }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func hex(_ color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

/// A small live picture of the chosen look.
private struct LookPreview: View {
    private let look = LookSample.shared

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            if look.background.takesEffects && look.halftone {
                EffectPattern(effect: look.effect, density: look.density)
                    .opacity(0.3)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("KAIROS").font(KFont.label).tracking(2).foregroundStyle(Palette.inkFaint)
                Text("Not more time. The right time.").font(KFont.display(22)).foregroundStyle(Palette.ink)
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(Palette.surfaceRaised).frame(width: 150, height: 26)
                        Capsule().fill(Palette.gold.opacity(0.85)).frame(width: 110, height: 26)
                            .frame(width: 190, alignment: .trailing)
                    }
                    Spacer()
                    KipPreview(style: look.kip, size: 64)
                }
            }
            .padding(16)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Text("Live preview").font(KFont.ui(12, .medium, relativeTo: .caption)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 10).frame(height: 26).kGlass(Capsule()).padding(12)
        }
        .animation(Motion.snappy, value: look.background)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(look.background.title) background")
    }

    @ViewBuilder
    private var backdrop: some View {
        switch look.background {
        case .kairos:
            ZStack {
                Palette.ground
                RadialGradient(colors: [Palette.glow, Palette.glow.opacity(0)], center: .topTrailing, startRadius: 0, endRadius: 260)
            }
        case .color:
            look.baseColor.overlay(Palette.ground.opacity(0.25))
        case .image:
            if let image = look.image {
                Image(uiImage: image).resizable().scaledToFill().overlay(Palette.ground.opacity(look.imageTint))
            } else {
                Palette.surface2
            }
        case .flow:
            AngularGradient(colors: [look.baseColor, Palette.gold.opacity(0.6), look.baseColor.opacity(0.7), look.baseColor], center: .center, angle: .degrees(look.swirl * 360))
                .blur(radius: 18 + look.distortion * 20)
        case .glass:
            ZStack {
                LinearGradient(colors: wallpaperColors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial).opacity(look.glass)
                    .padding(28)
            }
        case .animated:
            ZStack {
                Palette.night
                EffectPattern(effect: .ascii, density: 10).opacity(0.6)
            }
        }
    }

    private var wallpaperColors: [UInt32] {
        LookSample.wallpapers.first { $0.name == look.wallpaper }?.colors ?? [0x1F6F78, 0x6FB3B8]
    }
}

/// Dots, glyphs or a dither grid, drawn for the preview and thumbnails.
private struct EffectPattern: View {
    let effect: LookEffect
    let density: Double

    var body: some View {
        Canvas { context, size in
            let cell = CGFloat(max(4, density * 1.6))
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0 || effect != .halftone) ? 0 : cell / 2
                var column = 0
                while x < size.width {
                    let fade = 1 - (y / size.height) * 0.7
                    switch effect {
                    case .halftone, .dithered:
                        let radius = effect == .halftone ? cell * 0.32 * fade : cell * 0.22
                        if effect == .halftone || (row + column) % 2 == 0 {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(Palette.goldText))
                        }
                    case .ascii, .numbers, .binary:
                        let glyphs: [String] = effect == .ascii ? ["#", "*", "+", ":", "."] : (effect == .numbers ? ["3", "7", "1", "9", "4"] : ["0", "1"])
                        let glyph = glyphs[(row * 7 + column * 3) % glyphs.count]
                        context.draw(Text(glyph).font(.system(size: cell * 0.9, design: .monospaced)).foregroundStyle(Palette.goldText),
                                     at: CGPoint(x: x + cell / 2, y: y + cell / 2))
                    }
                    x += cell
                    column += 1
                }
                y += cell
                row += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HalftoneThumb: View {
    let seed: Int
    let custom: Bool

    var body: some View {
        ZStack {
            custom ? Palette.surface2 : Palette.groundDeep
            EffectPattern(effect: .halftone, density: Double(4 + seed % 3))
                .opacity(custom ? 0.9 : 0.5)
        }
    }
}

/// Kip in each of the four styles, built from the real Mascot.
struct KipPreview: View {
    let style: KipStyle
    var size: CGFloat = 50

    var body: some View {
        switch style {
        case .flat:
            Mascot(size: size)
        case .halftone:
            Mascot(size: size)
                .mask { KipDotMask(cell: max(3, size / 14), round: true) }
        case .pixel:
            Mascot(size: size)
                .mask { KipDotMask(cell: max(3, size / 10), round: false) }
        case .hidden:
            Circle().fill(Palette.gold).frame(width: size * 0.22, height: size * 0.22)
                .overlay(Circle().strokeBorder(Palette.ink.opacity(0.3), lineWidth: 1))
        }
    }
}

private struct KipDotMask: View {
    let cell: CGFloat
    let round: Bool

    var body: some View {
        Canvas { context, canvas in
            var y: CGFloat = 0
            var row = 0
            while y < canvas.height {
                var x: CGFloat = (round && row % 2 == 1) ? cell / 2 : 0
                while x < canvas.width {
                    let rect = CGRect(x: x, y: y, width: cell * (round ? 0.86 : 0.88), height: cell * (round ? 0.86 : 0.88))
                    context.fill(round ? Path(ellipseIn: rect) : Path(rect), with: .color(.black))
                    x += cell
                }
                y += cell
                row += 1
            }
        }
    }
}

private struct AppIconPreview: View {
    let icon: LookAppIcon

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous).fill(background)
            Mascot(size: 40, stage: background)
                .environment(\.colorScheme, icon == .parchment || icon == .gold ? .light : .dark)
        }
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }

    private var background: Color {
        switch icon {
        case .kairos: Color(hex: 0x2A1E17)
        case .night: Palette.night
        case .parchment: Palette.paper
        case .gold: Color(hex: 0xE2B154)
        }
    }
}

// MARK: - Layout

nonisolated struct HomePart: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var detail: String
    var shown: Bool
}

nonisolated struct SidebarTab: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var group: String
    var shown: Bool
}

@Observable
final class LayoutSample {
    static let shared = LayoutSample()

    static let defaultHome: [HomePart] = [
        HomePart(id: "glance", title: "Glance row", detail: "Model use and the next event", shown: true),
        HomePart(id: "pinned", title: "Pinned bots", detail: "Big faces with their status", shown: true),
        HomePart(id: "chats", title: "Conversations", detail: "Every chat, newest first", shown: true),
        HomePart(id: "crm", title: "CRM card", detail: "From your CRM tab", shown: false),
        HomePart(id: "board", title: "Team board card", detail: "From your Team board tab", shown: false),
    ]
    static let defaultSidebar: [SidebarTab] = [
        SidebarTab(id: "home", title: "Home", group: "Top", shown: true),
        SidebarTab(id: "chats", title: "Chats", group: "Top", shown: true),
        SidebarTab(id: "notes", title: "Notes", group: "Workspace", shown: true),
        SidebarTab(id: "library", title: "Library", group: "Workspace", shown: true),
        SidebarTab(id: "calendar", title: "Calendar", group: "Workspace", shown: true),
        SidebarTab(id: "email", title: "Email", group: "Workspace", shown: true),
        SidebarTab(id: "tasks", title: "Tasks", group: "Workspace", shown: true),
        SidebarTab(id: "store", title: "Tool Store", group: "Intelligence", shown: true),
        SidebarTab(id: "cookbook", title: "Cookbook", group: "Intelligence", shown: false),
        SidebarTab(id: "crm", title: "CRM", group: "Intelligence", shown: true),
    ]
    static let defaultPins = ["notes", "library", "calendar", "email", "tasks"]

    var home = LayoutSample.defaultHome
    var sidebar = LayoutSample.defaultSidebar
    var pins = LayoutSample.defaultPins

    func moveHome(_ index: Int, by delta: Int) {
        let target = index + delta
        guard home.indices.contains(target) else { return }
        home.swapAt(index, target)
    }

    func movePin(_ index: Int, by delta: Int) {
        let target = index + delta
        guard pins.indices.contains(target) else { return }
        pins.swapAt(index, target)
    }

    /// Moving across a group edge moves the tab into that group.
    func moveSidebar(_ index: Int, by delta: Int) {
        let target = index + delta
        guard sidebar.indices.contains(target) else { return }
        let group = sidebar[target].group
        sidebar.swapAt(index, target)
        sidebar[target].group = group
    }

    func title(of id: String) -> String { sidebar.first { $0.id == id }?.title ?? id }
}

struct LayoutScreen: View {
    @Environment(AppRouter.self) private var router
    @Bindable private var layout = LayoutSample.shared

    var body: some View {
        SettingsPage("Layout", subtitle: "What sits on the tab bar and on Home. Every change saves at once.") {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "The tab bar").padding(.leading, 6)
                barPreview
                Text("Home, Make, Library and Desktop always stay. Hold the bar to open Jump to, then drag any area onto it to keep it there.")
                    .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsGroup("Shortcut on the bar", footer: "One shortcut fits beside the tabs. It opens that area's one home.") {
                ForEach(JumpArea.allCases) { area in
                    shortcutRow(area)
                }
            }

            SettingsGroup("Home", footer: "Hidden parts come back any time. Tab cards start hidden.") {
                ForEach(Array(layout.home.enumerated()), id: \.element.id) { index, part in
                    LayoutMoveRow(title: part.title, detail: part.detail,
                                  shown: Binding(get: { layout.home[index].shown }, set: { layout.home[index].shown = $0 }),
                                  canUp: index > 0, canDown: index < layout.home.count - 1, locked: false) { delta in
                        withAnimation(Motion.snappy) { layout.moveHome(index, by: delta) }
                    }
                }
                ActionRow(title: "Reset Home", symbol: "arrow.counterclockwise") {
                    withAnimation(Motion.snappy) { layout.home = LayoutSample.defaultHome }
                    YouStore.shared.say("Home is back to the start")
                }
            }

            SettingsGroup("Your desktop's pinned strip", footer: "The tab icons under Search in the desktop sidebar.") {
                if layout.pins.isEmpty { EmptyRow(text: "Nothing pinned yet.") }
                ForEach(Array(layout.pins.enumerated()), id: \.element) { index, id in
                    pinRow(index: index, id: id)
                }
                if !unpinned.isEmpty {
                    Menu {
                        ForEach(unpinned) { tab in
                            Button(tab.title) { withAnimation(Motion.snappy) { layout.pins.append(tab.id) } }
                        }
                    } label: {
                        RowLabel(title: "Pin a tab", symbol: "plus", tint: Palette.goldText, titleColor: Palette.goldText)
                            .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                    }
                }
            }

            SettingsGroup("Your desktop's sidebar", footer: "Home always shows. The arrows move a tab across groups.") {
                ForEach(Array(layout.sidebar.enumerated()), id: \.element.id) { index, tab in
                    LayoutMoveRow(title: tab.title, detail: tab.group,
                                  shown: Binding(get: { layout.sidebar[index].shown }, set: { layout.sidebar[index].shown = $0 }),
                                  canUp: index > 0, canDown: index < layout.sidebar.count - 1, locked: tab.id == "home") { delta in
                        withAnimation(Motion.snappy) { layout.moveSidebar(index, by: delta) }
                    }
                }
                ActionRow(title: "Reset sidebar", symbol: "arrow.counterclockwise") {
                    withAnimation(Motion.snappy) {
                        layout.sidebar = LayoutSample.defaultSidebar
                        layout.pins = LayoutSample.defaultPins
                    }
                    YouStore.shared.say("Sidebar is back to the start")
                }
            }
        }
    }

    private var unpinned: [SidebarTab] {
        layout.sidebar.filter { $0.shown && $0.id != "home" && !layout.pins.contains($0.id) }
    }

    private func shortcutRow(_ area: JumpArea) -> some View {
        let on = router.pinned.contains(area)
        return Button {
            Haptics.select()
            withAnimation(Motion.snappy) {
                if on { router.unpin(area) } else { router.pin(area) }
            }
        } label: {
            HStack {
                RowLabel(title: area.title, detail: area.about, symbol: area.symbol)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Palette.goldText : Palette.inkFaint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func pinRow(index: Int, id: String) -> some View {
        HStack(spacing: 2) {
            RowLabel(title: layout.title(of: id))
            LayoutArrow(symbol: "arrow.up", enabled: index > 0, label: "Move \(layout.title(of: id)) up") {
                withAnimation(Motion.snappy) { layout.movePin(index, by: -1) }
            }
            LayoutArrow(symbol: "arrow.down", enabled: index < layout.pins.count - 1, label: "Move \(layout.title(of: id)) down") {
                withAnimation(Motion.snappy) { layout.movePin(index, by: 1) }
            }
            PillButton(title: "Unpin") {
                withAnimation(Motion.snappy) { layout.pins.removeAll { $0 == id } }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4).frame(minHeight: 52)
    }

    private var barPreview: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(AppTab.allCases) { tab in
                    Image(systemName: tab.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(tab == .home ? Palette.ink : Palette.inkDim)
                        .frame(width: 46, height: 40)
                        .background { if tab == .home { Capsule().fill(Palette.ink.opacity(0.15)) } }
                }
                ForEach(router.pinned) { area in
                    Image(systemName: area.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 44, height: 40)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(5)
            .kGlass(RoundedRectangle(cornerRadius: 25, style: .continuous))
            Spacer(minLength: 0)
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Palette.onGold)
                .frame(width: 50, height: 50)
                .background(LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
        }
        .padding(14)
        .kCard(radius: 22)
        .animation(Motion.bouncy, value: router.pinned)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(barLabel)
    }

    private var barLabel: String {
        let extra = router.pinned.map(\.title).joined(separator: ", ")
        return "The tab bar: Home, Make, Library, Desktop" + (extra.isEmpty ? "" : ", and \(extra)")
    }
}

private struct LayoutArrow: View {
    let symbol: String
    let enabled: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Palette.ink : Palette.inkFaint.opacity(0.4))
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// A row with up and down arrows and a show switch.
private struct LayoutMoveRow: View {
    let title: String
    let detail: String
    @Binding var shown: Bool
    let canUp: Bool
    let canDown: Bool
    let locked: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KFont.ui(16)).foregroundStyle(shown ? Palette.ink : Palette.inkFaint)
                    .strikethrough(!shown, color: Palette.inkFaint)
                Text(locked ? "Always shows" : detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 4)
            LayoutArrow(symbol: "arrow.up", enabled: canUp, label: "Move \(title) up") { move(-1) }
            LayoutArrow(symbol: "arrow.down", enabled: canDown, label: "Move \(title) down") { move(1) }
            if !locked {
                Toggle("Show \(title)", isOn: Binding(get: { shown }, set: { value in
                    Haptics.select()
                    withAnimation(Motion.snappy) { shown = value }
                }))
                .labelsHidden()
                .tint(Palette.gold)
                .padding(.leading, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
    }
}

enum LookDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "look": return AnyView(LookScreen())
        case "look-color": return AnyView(LookScreen(start: .color))
        case "look-flow": return AnyView(LookScreen(start: .flow))
        case "look-glass": return AnyView(LookScreen(start: .glass))
        case "look-animated": return AnyView(LookScreen(start: .animated))
        case "look-image": return AnyView(LookScreen(start: .image))
        case "layout": return AnyView(LayoutScreen())
        default: return nil
        }
    }
}
