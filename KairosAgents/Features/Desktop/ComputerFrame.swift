import SwiftUI
import UIKit

/// The live screen of a computer, while paired: the last picture the stream sent, kept in memory only. A picture
/// that is not live is dimmed and marked with its time, so an old frame never passes as the live one. Pinch to
/// zoom, drag to look around when zoomed in. Nothing here saves, shares or sends the picture.
struct DeskComputerPicture: View {
    let image: UIImage?
    let phase: DeskComputerPhase
    let lastEvent: Date?
    let pictureTime: Date?
    let closedAt: Date?
    /// The app is not in front: the picture is covered.
    let shielded: Bool

    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fresh = phase == .live && (lastEvent.map { context.date.timeIntervalSince($0) < 8 } ?? false)
            let mark = label(fresh)
            Color.black
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        ZStack {
                            if let image {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .scaleEffect(zoom)
                                    .offset(pan)
                            } else {
                                empty
                            }
                            if mark != nil { Color.black.opacity(0.4).allowsHitTesting(false) }
                            if let mark {
                                Text(mark)
                                    .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                                    .foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .kGlass(Capsule())
                                    .padding(10)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                    .allowsHitTesting(false)
                            }
                            if shielded { Palette.ground }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(drag(geometry.size), including: zoom > 1.01 ? .all : .none)
                        .simultaneousGesture(pinch)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(fresh ? Palette.gold : Palette.line, lineWidth: fresh ? 2 : 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shielded ? "The computer's screen is hidden while Kairos is in the background" : "The computer's screen")
    }

    @ViewBuilder
    private var empty: some View {
        switch phase {
        case .connecting, .idle:
            VStack(spacing: 8) {
                ProgressView().tint(Palette.cream)
                Text("Opening the live screen").font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.cream)
            }
        case .paused:
            Text("Paused while Kairos is in the background")
                .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.cream)
        default:
            VStack(spacing: 8) {
                Image(systemName: "photo").font(.system(size: 22, weight: .medium)).foregroundStyle(Palette.cream)
                Text("No picture yet").font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.cream)
            }
        }
    }

    /// What marks a picture that is not live, or nil when it is.
    private func label(_ fresh: Bool) -> String? {
        guard image != nil else { return nil }
        switch phase {
        case .idle: return nil
        case .live where fresh: return nil
        case .closed: return "Computer closed. Last picture " + Self.time(closedAt ?? pictureTime)
        default: return "Not live. Last picture " + Self.time(pictureTime)
        }
    }

    private static func time(_ date: Date?) -> String {
        guard let date else { return "earlier" }
        return "at " + date.formatted(date: .omitted, time: .standard)
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = min(max(1, pinchBase * value.magnification), 4) }
            .onEnded { _ in
                pinchBase = zoom
                if zoom <= 1.01 {
                    withAnimation(Motion.snappy) {
                        zoom = 1
                        pan = .zero
                    }
                    pinchBase = 1
                    panBase = .zero
                }
            }
    }

    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let maxX = size.width * (zoom - 1) / 2
                let maxY = size.height * (zoom - 1) / 2
                pan = CGSize(width: min(max(-maxX, panBase.width + value.translation.width), maxX),
                             height: min(max(-maxY, panBase.height + value.translation.height), maxY))
            }
            .onEnded { _ in panBase = pan }
    }
}

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
