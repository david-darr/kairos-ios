import SwiftUI
import UIKit

/// The Kairos colours ("Parchment and Bistre"), for the night look and the light look.
/// Night is deep brown with cream ink and gold; light is parchment with bistre ink.
nonisolated enum Palette {
    // Grounds
    static let ground = dyn(0x1B1612, 0xF3EADB)
    static let groundDeep = dyn(0x120E0B, 0xE9DDC9)
    static let glow = dyn(0x4A3524, 0xFBF6EE)

    // Surfaces drawn inside the content (cards, bubbles). Chrome uses real glass.
    static let surface = dyn(0xF2E8D8, 0xFBF6EE, 0.065, 0.78)
    static let surfaceRaised = dyn(0xF2E8D8, 0xFBF6EE, 0.11, 0.95)
    static let surfaceSolid = dyn(0x2A221C, 0xFBF6EE)
    static let surface2 = dyn(0x3A3029, 0xEDE2D0)
    static let line = dyn(0xF2E8D8, 0xB8893B, 0.11, 0.30)
    static let lineStrong = dyn(0xF2E8D8, 0xB8893B, 0.2, 0.5)

    // Ink
    static let ink = dyn(0xF2E8D8, 0x3A2A20)
    static let inkDim = dyn(0xC9BBA8, 0x6B5646)
    static let inkFaint = dyn(0xA8998A, 0x7A6553)

    // Gold: the point of the brand
    static let gold = dyn(0xE2B154, 0xB8893B)
    static let goldHi = dyn(0xEDC274, 0xD9B260)
    static let goldDeep = dyn(0xC9933A, 0x9C7430)
    static let goldText = dyn(0xE2B154, 0x83601F)
    static let onGold = Color(hex: 0x1B1612)

    // States
    static let working = dyn(0x8CB8D9, 0x4F84A8)
    static let success = dyn(0x6FBF73, 0x4F6E4A)
    static let danger = dyn(0xE8836E, 0xA8432F)
    static let hangUp = Color(hex: 0xC2412C)

    // Glass tints: a warm wash so the glass stays in the Kairos colours
    static let glassTint = dyn(0x3A2E26, 0xFBF6EE, 0.38, 0.35)
    static let glassTintStrong = dyn(0x342922, 0xFBF6EE, 0.62, 0.6)

    // Kip's own body follows the look: cream at night, bistre in the light look
    static let kipBody = dyn(0xF2E8D8, 0x3A2A20)
    static let kipEye = dyn(0x1B1612, 0xF3EADB)

    static let mascotShadow = dyn(0x000000, 0x3A2A20, 0.3, 0.13)

    // Fixed colours (same in both looks)
    static let cream = Color(hex: 0xF2E8D8)
    static let night = Color(hex: 0x1B1612)
    static let callTop = Color(hex: 0x2B2119)
    static let callBottom = Color(hex: 0x0D0A08)
    static let paper = Color(hex: 0xF5EFE4)

    /// The six bot pastels from the desktop app.
    static let botGold: UInt32 = 0xD9B260
    static let botPowder: UInt32 = 0xB9D2E3
    static let botSand: UInt32 = 0xE8C39E
    static let botRose: UInt32 = 0xD99A92
    static let botSage: UInt32 = 0xB5C7A5
    static let botLilac: UInt32 = 0xCDBFD9

    static func dyn(_ dark: UInt32, _ light: UInt32, _ darkAlpha: Double = 1, _ lightAlpha: Double = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

nonisolated extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

nonisolated extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Jost for the interface, Cormorant Garamond Italic for names and moments.
nonisolated enum KFont {
    enum Weight { case regular, medium, semibold }

    static func ui(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .regular: name = "Jost-Regular"
        case .medium: name = "Jost-Medium"
        case .semibold: name = "Jost-SemiBold"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("CormorantGaramond-SemiBoldItalic", size: size, relativeTo: style)
    }

    /// Small capital labels, like "THINKING" or "JUMP TO".
    static let label = ui(11.5, .medium, relativeTo: .caption2)
}

/// One motion language for the whole app.
nonisolated enum Motion {
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let bouncy = Animation.spring(response: 0.46, dampingFraction: 0.72)
    static let sheet = Animation.spring(response: 0.5, dampingFraction: 0.86)
    static let gentle = Animation.easeInOut(duration: 0.24)
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thud() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
