import SwiftUI
import UIKit

/// One sheet for the model, how hard it thinks, Fast, approval, details and favourites.
struct ModelSheet: View {
    @Binding var choice: ModelChoice
    @Namespace private var ns

    private let favourites: [(name: String, source: String)] = [
        ("Claude Opus", "Claude subscription"),
        ("GPT-6.1 Sol", "Codex"),
        ("Qwen local", "This PC"),
    ]

    var body: some View {
        FittedSheet(estimate: 690) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Model")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)

                HStack(spacing: 12) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 42, height: 42)
                        .background(Palette.ink.opacity(0.08), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(choice.name).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                        Text(choice.source).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                }
                .padding(14)
                .kCard(radius: 22, raised: true)

                VStack(spacing: 10) {
                    SectionLabel(text: "Thinking")
                    HStack(spacing: 0) {
                        ForEach(ModelChoice.levels, id: \.self) { level in
                            let on = level == choice.level
                            Button {
                                Haptics.select()
                                withAnimation(Motion.snappy) { choice.level = level }
                            } label: {
                                Text(level)
                                    .font(KFont.ui(14.5, on ? .semibold : .regular, relativeTo: .subheadline))
                                    .foregroundStyle(on ? Palette.onGold : Palette.inkDim)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background {
                                        if on { Capsule().fill(Palette.gold).matchedGeometryEffect(id: "level", in: ns) }
                                    }
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(4)
                    .kCard(radius: 26)
                }

                HStack(spacing: 10) {
                    toggleTile(symbol: "bolt.fill", title: "Fast", value: choice.fast ? "On" : "Off", on: choice.fast) {
                        choice.fast.toggle()
                    }
                    toggleTile(symbol: "checkmark.shield.fill", title: "Approve", value: choice.approval, on: false) {
                        choice.cycleApproval()
                    }
                }

                VStack(spacing: 8) {
                    HStack {
                        Text("Details").font(KFont.ui(15.5, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("79K of 500K").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.ink.opacity(0.1))
                            HStack(spacing: 2) {
                                Capsule().fill(Palette.inkFaint).frame(width: geometry.size.width * 0.02)
                                Capsule().fill(Color(hex: Palette.botSand)).frame(width: geometry.size.width * 0.03)
                                Capsule().fill(Color(hex: Palette.botSage)).frame(width: geometry.size.width * 0.01)
                                Capsule().fill(Palette.working).frame(width: geometry.size.width * 0.1)
                            }
                        }
                    }
                    .frame(height: 8)
                }
                .padding(14)
                .kCard(radius: 20)

                VStack(spacing: 10) {
                    HStack {
                        SectionLabel(text: "Favourites")
                        Text("All models").font(KFont.ui(14, .medium, relativeTo: .footnote)).foregroundStyle(Palette.goldText)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(favourites.enumerated()), id: \.offset) { index, model in
                            Button {
                                Haptics.select()
                                withAnimation(Motion.snappy) {
                                    choice.name = model.name
                                    choice.source = model.source
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(model.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                        Text(model.source).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                    }
                                    Spacer()
                                    if model.name == choice.name {
                                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.goldText)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 56)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if index < favourites.count - 1 { Palette.line.frame(height: 1).padding(.leading, 16) }
                                }
                            }
                            .buttonStyle(PressStyle(scale: 0.99))
                        }
                    }
                    .kCard(radius: 20)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private func toggleTile(symbol: String, title: String, value: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(on ? Palette.onGold : Palette.ink)
                    .frame(width: 34, height: 34)
                    .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(KFont.ui(15.5, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                    Text(value)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(on ? Palette.goldText : Palette.inkFaint)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .kCard(radius: 20, raised: on)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(title): \(value)")
    }
}

/// Everything a chat can do, from the + button.
struct ToolsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let tools: [(symbol: String, title: String, detail: String)] = [
        ("doc", "Files", "From your phone, Library or the vault"),
        ("globe", "Browse the web", "Watch it work in a live card"),
        ("desktopcomputer", "Use my computer", "Click and type on your desktop"),
        ("paintpalette", "Design", "A page, a post or a screen, on a canvas"),
        ("doc.text", "Document", "A doc, deck or sheet you can export"),
        ("clock", "Run in the background", "Keep going after you leave"),
        ("bolt", "Use a skill", "Saved ways of doing a job"),
        ("line.3.horizontal", "More", "Workspace, integrations, open mic, compact"),
    ]

    private let photoTints: [(UInt32, UInt32)] = [(0x6B5442, 0x3C2E24), (0x4E6070, 0x2C3640), (0x6E5A3A, 0x3A2E1E), (0x5A4A5E, 0x2E2633)]

    var body: some View {
        FittedSheet(estimate: 690) {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        VStack(spacing: 5) {
                            Image(systemName: "camera").font(.system(size: 20, weight: .medium))
                            Text("Camera").font(KFont.ui(12.5, relativeTo: .caption))
                        }
                        .foregroundStyle(Palette.ink)
                        .frame(width: 84, height: 84)
                        .kCard(radius: 18, raised: true)
                        ForEach(Array(photoTints.enumerated()), id: \.offset) { _, tint in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LinearGradient(colors: [Color(hex: tint.0), Color(hex: tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 84, height: 84)
                                .accessibilityLabel("Recent photo")
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .scrollIndicators(.hidden)
                .padding(.top, 34)

                VStack(spacing: 0) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                        Button { dismiss() } label: {
                            HStack(spacing: 14) {
                                Image(systemName: tool.symbol)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                    .frame(width: 40, height: 40)
                                    .background(Palette.ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tool.title).font(KFont.ui(16.5)).foregroundStyle(Palette.ink)
                                    Text(tool.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if index < tools.count - 1 { Palette.line.frame(height: 1).padding(.leading, 54) }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        .arrives(index)
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 20)
        }
    }
}

/// The file viewer: "n of N", Copy and Share, a details pill, the file large on a light panel,
/// thumbnails bottom left, and sideways swipes between files.
struct DocumentViewer: View {
    let documents: [ChatDocument]
    @State var index: Int
    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Text("\(index + 1) of \(documents.count)")
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    Spacer()
                    Button {
                        UIPasteboard.general.string = documents[index].name
                        Haptics.success()
                        withAnimation(Motion.snappy) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.4))
                            withAnimation(Motion.snappy) { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Copy")
                    ShareLink(item: documents[index].name) {
                        Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Share")
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.ink)
            }
            .padding(.top, 28)
            .padding(.horizontal, 12)

            HStack(spacing: 10) {
                Text(documents[index].label).font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(Palette.ink)
                ForEach(documents[index].details, id: \.self) { detail in
                    Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .kCard(radius: 14)
            .padding(.horizontal, 16)

            TabView(selection: $index) {
                ForEach(Array(documents.enumerated()), id: \.offset) { offset, document in
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0xF4F1EC))
                        DocumentArt(look: document.look)
                            .aspectRatio(document.look == .page ? 0.77 : 1.6, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                            .padding(document.look == .page ? 28 : 0)
                    }
                    .padding(.horizontal, 16)
                    .tag(offset)
                    .accessibilityLabel(document.name)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(Array(documents.enumerated()), id: \.offset) { offset, document in
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) { index = offset }
                    } label: {
                        DocumentArt(look: document.look)
                            .frame(width: 56, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(offset == index ? Palette.gold : Palette.line, lineWidth: offset == index ? 2 : 1))
                            .scaleEffect(offset == index ? 1.06 : 1)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Show \(document.name)")
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
        .animation(Motion.snappy, value: index)
    }
}
