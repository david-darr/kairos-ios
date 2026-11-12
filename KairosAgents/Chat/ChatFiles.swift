import SwiftUI
import UIKit
import QuickLook

// Real files in a chat: the fanned stack in the conversation and the viewer sheet over it.
// Sample files are drawn (`DocumentArt`); real ones are read from the desktop when first shown.

/// Bytes of files already read from the desktop, kept while the app is open.
final class FileCache {
    static let shared = FileCache()
    private var store: [String: Data] = [:]
    private var order: [String] = []

    func data(_ id: String) -> Data? { store[id] }

    func keep(_ data: Data, for id: String) {
        // Small files only, and at most 40 of them.
        guard data.count < 12_000_000 else { return }
        if store[id] == nil { order.append(id) }
        store[id] = data
        while order.count > 40 { store[order.removeFirst()] = nil }
    }

    /// The file written where QuickLook and the share sheet can read it.
    static func temporaryURL(for file: ChatFile, data: Data) -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-files", isDirectory: true)
            .appendingPathComponent(String(abs(file.id.hashValue)), isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = file.name.replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent(safe.isEmpty ? "file" : safe)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// What a file looks like on a card: its picture, the sample drawing, or a paper tile with its type.
struct FileArt: View {
    let file: ChatFile
    let load: (ChatFile) async throws -> Data
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let look = file.sampleLook {
                DocumentArt(look: look)
            } else if let image {
                Color(hex: 0xF4F1EC)
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Palette.paper
                VStack(spacing: 8) {
                    Text(file.ext.isEmpty ? "FILE" : file.ext)
                        .font(KFont.ui(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.cream)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Palette.night.opacity(0.75), in: Capsule())
                    Text(file.name)
                        .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                        .foregroundStyle(Palette.night)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                    if file.missing {
                        Text("No longer available").font(KFont.ui(11.5, relativeTo: .caption2)).foregroundStyle(Palette.night.opacity(0.6))
                    }
                }
            }
        }
        .task(id: file.id) {
            guard file.sampleLook == nil, file.kind == .image, image == nil, !file.missing else { return }
            if let data = file.local ?? FileCache.shared.data(file.id) {
                image = UIImage(data: data)
                return
            }
            if let data = try? await load(file) {
                FileCache.shared.keep(data, for: file.id)
                image = UIImage(data: data)
            }
        }
    }
}

/// Files arrive as a fanned stack. Swipe the top card and it goes to the back; tap to open the viewer.
struct FileStack: View {
    let files: [ChatFile]
    let load: (ChatFile) async throws -> Data
    let open: (ChatFile) -> Void

    @State private var top = 0
    @State private var drag: CGSize = .zero

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                ForEach((0..<min(3, files.count)).reversed(), id: \.self) { depth in
                    let index = (top + depth) % files.count
                    FileArt(file: files[index], load: load)
                        .frame(width: 236, height: 178)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 14, y: 9)
                        .rotationEffect(.degrees(depth == 0 ? Double(drag.width) / 22 : Double(depth) * 3.6))
                        .offset(x: depth == 0 ? drag.width : CGFloat(depth) * 11, y: depth == 0 ? drag.height * 0.3 : CGFloat(depth) * 3)
                        .zIndex(Double(3 - depth))
                }
            }
            .frame(width: 262, height: 196, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { open(files[top % files.count]) }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        if abs(value.translation.width) > 70, files.count > 1 {
                            Haptics.select()
                            withAnimation(Motion.bouncy) {
                                top = (top + 1) % files.count
                                drag = .zero
                            }
                        } else {
                            withAnimation(Motion.bouncy) { drag = .zero }
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("\(files[top % files.count].name), \(top % files.count + 1) of \(files.count). Swipe for the next file")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(files[top % files.count]) }

            VStack(alignment: .leading, spacing: 6) {
                Text("\(top % files.count + 1) of \(files.count)")
                    .font(KFont.ui(12.5, relativeTo: .caption))
                    .foregroundStyle(Palette.inkFaint)
                    .contentTransition(.numericText())
                    .padding(.top, 4)
                Button { open(files[top % files.count]) } label: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 40)
                        .background(Palette.ink.opacity(0.1), in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Open \(files[top % files.count].name) to save or share it")
            }
        }
        .padding(.vertical, 6)
        .onChange(of: files.count) { top = 0 }
    }
}

/// The file viewer: "n of N", Copy and Share, a details pill, the file large on a light panel,
/// thumbnails bottom left, and sideways swipes between files.
struct FileViewer: View {
    let files: [ChatFile]
    @State var index: Int
    let load: (ChatFile) async throws -> Data

    @State private var copied = false
    @State private var shareURL: URL?

    private var current: ChatFile { files[min(max(0, index), files.count - 1)] }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Text("\(index + 1) of \(files.count)")
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    Spacer()
                    Button(action: copy) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(current.kind == .image ? "Copy image" : "Copy name")
                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Share or save")
                    } else {
                        ShareLink(item: current.name) {
                            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Share")
                    }
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.ink)
            }
            .padding(.top, 28)
            .padding(.horizontal, 12)

            HStack(spacing: 10) {
                Text(current.label(at: index)).font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(Palette.ink)
                Text(current.name).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim).lineLimit(1)
                ForEach(current.details, id: \.self) { detail in
                    Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .kCard(radius: 14)
            .padding(.horizontal, 16)

            TabView(selection: $index) {
                ForEach(Array(files.enumerated()), id: \.offset) { offset, file in
                    FilePage(file: file, load: load) { url in
                        if offset == index { shareURL = url }
                    }
                    .padding(.horizontal, 16)
                    .tag(offset)
                    .accessibilityLabel(file.name)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if files.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(files.enumerated()), id: \.offset) { offset, file in
                            Button {
                                Haptics.select()
                                withAnimation(Motion.snappy) { index = offset }
                            } label: {
                                FileArt(file: file, load: load)
                                    .frame(width: 56, height: 42)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(offset == index ? Palette.gold : Palette.line, lineWidth: offset == index ? 2 : 1))
                                    .scaleEffect(offset == index ? 1.06 : 1)
                                    .frame(height: 48)
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Show \(file.name)")
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 12)
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .animation(Motion.snappy, value: index)
        .onChange(of: index) { shareURL = nil }
    }

    private func copy() {
        if current.kind == .image, let data = current.local ?? FileCache.shared.data(current.id), let image = UIImage(data: data) {
            UIPasteboard.general.image = image
        } else {
            UIPasteboard.general.string = current.name
        }
        Haptics.success()
        withAnimation(Motion.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(Motion.snappy) { copied = false }
        }
    }
}

/// One file, large: a picture you can pinch, a system preview for documents, or the sample drawing.
private struct FilePage: View {
    let file: ChatFile
    let load: (ChatFile) async throws -> Data
    let ready: (URL) -> Void

    private enum Phase { case loading, image(UIImage), preview(URL), failed(String) }
    @State private var phase: Phase = .loading
    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0xF4F1EC))
            if let look = file.sampleLook {
                DocumentArt(look: look)
                    .aspectRatio(look == .page ? 0.77 : 1.6, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    .padding(look == .page ? 28 : 0)
            } else {
                switch phase {
                case .loading:
                    ProgressView().tint(Palette.night)
                case .image(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(min(6, max(1, zoom * pinch)))
                        .gesture(
                            MagnifyGesture()
                                .onChanged { pinch = $0.magnification }
                                .onEnded { value in
                                    zoom = min(6, max(1, zoom * value.magnification))
                                    pinch = 1
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(Motion.snappy) { zoom = zoom > 1 ? 1 : 2.5 }
                        }
                        .padding(6)
                        .accessibilityHint("Pinch or double tap to zoom")
                case .preview(let url):
                    QuickLookPreview(url: url)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                case .failed(let reason):
                    VStack(spacing: 6) {
                        Image(systemName: "doc.questionmark").font(.system(size: 26)).foregroundStyle(Palette.night.opacity(0.6))
                        Text("Preview unavailable.")
                            .font(KFont.ui(15.5, .medium))
                            .foregroundStyle(Palette.night)
                        Text(reason)
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.night.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task(id: file.id) { await open() }
    }

    private func open() async {
        guard file.sampleLook == nil else { return }
        if file.missing {
            phase = .failed("This file is no longer on your desktop.")
            return
        }
        do {
            let data: Data
            if let known = file.local ?? FileCache.shared.data(file.id) {
                data = known
            } else {
                data = try await load(file)
                FileCache.shared.keep(data, for: file.id)
            }
            let url = FileCache.temporaryURL(for: file, data: data)
            if let url { ready(url) }
            if file.kind == .image, let image = UIImage(data: data) {
                phase = .image(image)
            } else if let url {
                phase = .preview(url)
            } else {
                phase = .failed("The file could not be opened on this iPhone.")
            }
        } catch {
            phase = .failed(error.plainWords)
        }
    }
}

/// The system's own preview for documents, sheets, decks, PDFs, text, audio and video.
private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
