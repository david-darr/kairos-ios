import SwiftUI

/// One frame of the desktop screen, drawn from sample data at 16 by 10.
/// Everything is laid out in the PC's own 1280 by 800 space and scaled to fit.
struct ComputerFrame: View {
    var typed: String
    var scroll: CGFloat = 0
    var marker: CGPoint? = nil
    var showCaret = false

    var body: some View {
        GeometryReader { geometry in
            let s = geometry.size.width / 1280
            ZStack(alignment: .topLeading) {
                wallpaper
                browserWindow(s)
                    .frame(width: 640 * s, height: 520 * s)
                    .offset(x: 560 * s, y: 150 * s)
                notesWindow(s)
                    .frame(width: 560 * s, height: 420 * s)
                    .offset(x: 110 * s, y: 80 * s)
                taskbar(s)
                    .frame(width: 1280 * s, height: 50 * s)
                    .offset(y: 750 * s)
                if let marker {
                    Circle()
                        .strokeBorder(Palette.danger, lineWidth: max(2, 4 * s))
                        .background(Circle().fill(Palette.danger.opacity(0.25)))
                        .frame(width: 46 * s, height: 46 * s)
                        .offset(x: marker.x * s - 23 * s, y: marker.y * s - 23 * s)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your desktop screen. A notes window and a shop page in a browser.")
    }

    private var wallpaper: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2B2119), Color(hex: 0x4A3524), Color(hex: 0x6B4E33)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Palette.gold.opacity(0.45), .clear], center: UnitPoint(x: 0.85, y: 0.15), startRadius: 0, endRadius: 420)
        }
    }

    private func titleBar(_ title: String, _ s: CGFloat) -> some View {
        HStack(spacing: 8 * s) {
            Text(title)
                .font(.system(size: 15 * s, weight: .medium))
                .foregroundStyle(Color(hex: 0x3A2A20))
                .lineLimit(1)
            Spacer(minLength: 0)
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2 * s)
                    .fill(index == 2 ? Color(hex: 0xC2412C).opacity(0.75) : Color(hex: 0x3A2A20).opacity(0.25))
                    .frame(width: 22 * s, height: 14 * s)
            }
        }
        .padding(.horizontal, 14 * s)
        .frame(height: 36 * s)
        .background(Color(hex: 0xE9DDC9))
    }

    private func notesWindow(_ s: CGFloat) -> some View {
        VStack(spacing: 0) {
            titleBar("Order notes - Notepad", s)
            HStack(spacing: 18 * s) {
                Text("File").font(.system(size: 13 * s))
                Text("Edit").font(.system(size: 13 * s))
                Text("View").font(.system(size: 13 * s))
                Spacer()
            }
            .foregroundStyle(Color(hex: 0x6B5646))
            .padding(.horizontal, 14 * s)
            .frame(height: 26 * s)
            .background(Color(hex: 0xF3EADB))
            VStack(alignment: .leading, spacing: 0) {
                Text(typed + (showCaret ? "|" : ""))
                    .font(.system(size: 19 * s, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x1B1612))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
            }
            .padding(16 * s)
            .background(Color(hex: 0xFBF6EE))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 18 * s, y: 8 * s)
    }

    private func browserWindow(_ s: CGFloat) -> some View {
        VStack(spacing: 0) {
            titleBar("Bike shop - Browser", s)
            HStack(spacing: 8 * s) {
                Image(systemName: "lock.fill").font(.system(size: 11 * s))
                Text("shop.example/products").font(.system(size: 13 * s))
                Spacer()
            }
            .foregroundStyle(Color(hex: 0x6B5646))
            .padding(.horizontal, 12 * s)
            .frame(height: 30 * s)
            .background(Capsule().fill(Color(hex: 0xF3EADB)).padding(.horizontal, 10 * s).padding(.vertical, 3 * s))
            .background(Color(hex: 0xE9DDC9))
            ZStack(alignment: .top) {
                Color(hex: 0xFBF6EE)
                VStack(alignment: .leading, spacing: 14 * s) {
                    Text("Bikes and parts")
                        .font(.system(size: 26 * s, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1B1612))
                    ForEach(Array(products.enumerated()), id: \.offset) { index, product in
                        HStack(spacing: 14 * s) {
                            RoundedRectangle(cornerRadius: 8 * s)
                                .fill(Color(hex: tileColors[index % tileColors.count]))
                                .frame(width: 84 * s, height: 64 * s)
                            VStack(alignment: .leading, spacing: 4 * s) {
                                Text(product.0).font(.system(size: 17 * s, weight: .medium))
                                Text(product.1).font(.system(size: 14 * s))
                                    .foregroundStyle(Color(hex: 0x6B5646))
                            }
                            .foregroundStyle(Color(hex: 0x1B1612))
                            Spacer()
                            Text("Add to cart")
                                .font(.system(size: 13 * s, weight: .medium))
                                .foregroundStyle(Color(hex: 0x1B1612))
                                .padding(.horizontal, 12 * s)
                                .padding(.vertical, 7 * s)
                                .background(Capsule().fill(Color(hex: 0xE2B154)))
                        }
                    }
                }
                .padding(22 * s)
                .offset(y: -scroll * s)
            }
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 18 * s, y: 8 * s)
    }

    private func taskbar(_ s: CGFloat) -> some View {
        HStack(spacing: 14 * s) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6 * s)
                    .fill(index == 1 || index == 2 ? Color(hex: 0xE2B154).opacity(0.85) : Color.white.opacity(0.22))
                    .frame(width: 30 * s, height: 30 * s)
            }
            Spacer()
            Text("9:41")
                .font(.system(size: 15 * s, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 18 * s)
        .background(Color.black.opacity(0.55))
    }

    private let products = [
        ("Blue bell", "Brass, rings loud"),
        ("City bike, red", "Seven gears, light frame"),
        ("Bike lock", "Hardened steel, two keys"),
        ("Rear light", "USB charged, 20 hours"),
        ("Saddle bag", "Waxed canvas, 8 litres"),
        ("Pump", "Fits both valve types"),
    ]

    private let tileColors: [UInt32] = [Palette.botPowder, Palette.botRose, Palette.botSage, Palette.botSand, Palette.botLilac, Palette.botGold]
}
