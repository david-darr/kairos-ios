import SwiftUI
import UIKit
import AVFoundation
import QuickLookThumbnailing

// Real pictures inside a chat while the phone is paired: a first-page or first-frame thumbnail for a file, and a card
// for each design that belongs to the chat. Not paired, nothing here runs and the chats are exactly the sample chats.
//
// What is held is held in memory only, under the desktop and account it was read from. It is emptied when the phone
// is unpaired and whenever a different desktop or account is paired. A thumbnail that cannot be made leaves the
// drawn card in place: no error line, no broken picture, and never a change to the connection's state.

/// Which desktop and which account everything here belongs to. nil while the phone shows sample data.
enum ChatThumbAccount {
    static var key: String? {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return nil }
        return desktop.address + "|" + desktop.username
    }
}

// MARK: - Thumbnails of files

/// The pictures made so far, and the reading that makes them. At most two things are read or drawn at a time.
final class ChatThumbLive {
    static let shared = ChatThumbLive()

    /// The most a document, deck, sheet or PDF may weigh before the drawn card stays (read whole, never in part).
    static let documentCap = 5_000_000
    /// A text file: its first 256 kB is enough for a first page; over 1 MB without a range the card stays.
    static let textStart = 262_144
    static let textWhole = 1_000_000
    /// A video: its first 4 MB when the desktop honours a range; without one, a file over 8 MB keeps the card.
    static let videoStart = 4_194_304
    static let videoWhole = 8_000_000

    private nonisolated struct Failure {
        var permanent: Bool
        var at: Date
    }

    private var account: String?
    private var images: [String: UIImage] = [:]
    private var order: [String] = []
    private var failures: [String: Failure] = [:]
    private var active = 0

    // MARK: Account

    /// Everything goes: the phone was unpaired, or a different desktop or account came.
    func reset() {
        images = [:]
        order = []
        failures = [:]
        account = ChatThumbAccount.key
    }

    private func current() -> String? {
        let key = ChatThumbAccount.key
        if account != key { reset() }
        return key
    }

    // MARK: What gets a thumbnail

    /// The kinds that have a first page or a first frame. Audio keeps its drawing: the system gives it no artwork cheaply.
    static func plan(for kind: ChatFile.Kind) -> ChatThumbPlan? {
        switch kind {
        case .pdf, .document, .deck, .sheet: return ChatThumbPlan(start: nil, whole: documentCap)
        case .text: return ChatThumbPlan(start: textStart, whole: textWhole)
        case .video: return ChatThumbPlan(start: videoStart, whole: videoWhole)
        case .image, .audio, .other: return nil
        }
    }

    static func wants(_ file: ChatFile) -> Bool {
        file.sampleLook == nil && !file.missing && plan(for: file.kind) != nil
    }

    private func cacheKey(_ account: String, _ chat: String, _ file: ChatFile) -> String {
        account + "|" + chat + "|" + file.id
    }

    /// A thumbnail already made for this file, if there is one.
    func cached(_ file: ChatFile, chat: String) -> UIImage? {
        guard let account = current() else { return nil }
        return images[cacheKey(account, chat, file)]
    }

    // MARK: Slots, the memory and the failures

    /// Wait for one of two places. false when the row left the screen first.
    private func takeSlot() async -> Bool {
        while active >= 2 {
            if Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(120))
        }
        if Task.isCancelled { return false }
        active += 1
        return true
    }

    private func remember(_ image: UIImage, _ key: String) {
        if images[key] == nil { order.append(key) }
        images[key] = image
        // A few dozen small pictures at most.
        while order.count > 30 { images[order.removeFirst()] = nil }
    }

    private func blocked(_ key: String) -> Bool {
        guard let failure = failures[key] else { return false }
        // A file too big or a file the system cannot draw stays as it is. A desktop that did not answer is asked again later.
        return failure.permanent || Date().timeIntervalSince(failure.at) < 90
    }

    private func fail(_ key: String, permanent: Bool) {
        failures[key] = Failure(permanent: permanent, at: Date())
    }

    // MARK: A file

    /// The thumbnail of one file of a chat, or nil to keep the drawn card. Cancelled when the row leaves the screen.
    func thumbnail(for file: ChatFile, chat: String) async -> UIImage? {
        guard ChatThumbLive.wants(file), let plan = ChatThumbLive.plan(for: file.kind),
              let account = current(), let client = Connection.shared.client else { return nil }
        let key = cacheKey(account, chat, file)
        if let hit = images[key] { return hit }
        if blocked(key) { return nil }
        // The transcript knows the size of a file the person sent: over the cap there is nothing to ask.
        if let size = file.size, plan.start == nil, size > plan.whole {
            fail(key, permanent: true)
            return nil
        }
        guard await takeSlot() else { return nil }
        defer { active -= 1 }
        guard ChatThumbAccount.key == account else { return nil }

        let request: URLRequest
        do {
            let download = file.kind != .pdf && file.kind != .text
            request = try client.chatThumbFileRequest(sessionId: chat, url: file.id, download: download,
                                                      rangeEnd: plan.start.map { $0 - 1 })
        } catch {
            fail(key, permanent: false)
            return nil
        }
        let fetched = await ChatThumbFetcher(plan: plan).run(request)
        guard !Task.isCancelled, ChatThumbAccount.key == account else { return nil }
        switch fetched {
        case .tooBig:
            fail(key, permanent: true)
            return nil
        case .failed:
            fail(key, permanent: false)
            return nil
        case .bytes(let data):
            let image = await ChatThumbLive.render(data, name: file.name, kind: file.kind)
            guard !Task.isCancelled, ChatThumbAccount.key == account else { return nil }
            guard let image else {
                fail(key, permanent: true)
                return nil
            }
            remember(image, key)
            return image
        }
    }

    /// A picture the phone cannot decode itself (an SVG, say), drawn by the system from bytes already read.
    func thumbnail(fromBytes data: Data, for file: ChatFile, chat: String) async -> UIImage? {
        guard file.sampleLook == nil, let account = current() else { return nil }
        let key = cacheKey(account, chat, file)
        if let hit = images[key] { return hit }
        if blocked(key) { return nil }
        guard await takeSlot() else { return nil }
        defer { active -= 1 }
        let image = await ChatThumbLive.render(data, name: file.name, kind: .other)
        guard !Task.isCancelled, ChatThumbAccount.key == account else { return nil }
        guard let image else {
            fail(key, permanent: true)
            return nil
        }
        remember(image, key)
        return image
    }

    // MARK: Making the picture

    /// Write the bytes where the system can read them, ask the system for the first page or frame, and delete the
    /// copy at once. Runs off the main thread and stops when the row leaves the screen.
    private static func render(_ data: Data, name: String, kind: ChatFile.Kind) async -> UIImage? {
        let work = Task.detached(priority: .utility) { () -> UIImage? in
            await ChatThumbLive.draw(data, name: name, kind: kind)
        }
        return await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private nonisolated static func draw(_ data: Data, name: String, kind: ChatFile.Kind) async -> UIImage? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-thumbs", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        // The copy is gone as soon as the picture is made, whatever the result.
        defer { try? FileManager.default.removeItem(at: folder) }

        // Only the extension of the desktop's name is used, so no odd name reaches the file system.
        let parts = name.split(separator: ".")
        let ext = parts.count > 1 ? String(parts[parts.count - 1]).lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) } : ""
        let url = folder.appendingPathComponent(ext.isEmpty || ext.count > 8 ? "file" : "file." + ext)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        if Task.isCancelled { return nil }
        if kind == .video { return await frame(of: url) }
        return await firstPage(of: url)
    }

    /// The system's own thumbnail for the file (never its generic icon).
    private nonisolated static func firstPage(of url: URL) async -> UIImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 236, height: 318), scale: 2, representationTypes: .thumbnail)
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.uiImage
        } catch {
            return nil
        }
    }

    /// The first frame of a video (or the one half a second in, when the first cannot be read).
    private nonisolated static func frame(of url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 472, height: 356)
        for seconds in [0.0, 0.5] {
            if Task.isCancelled { return nil }
            if let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
                return UIImage(cgImage: result.image)
            }
        }
        return nil
    }

    // MARK: A design's first board

    /// The picture of a design's first board. nil keeps the drawn card (the desktop answers 404 when it cannot draw it).
    func designImage(_ design: ChatThumbDesign) async -> UIImage? {
        guard let board = design.firstBoard, ChatThumbWire.isSlug(board),
              let account = current(), let client = Connection.shared.client else { return nil }
        let key = account + "|design|\(design.id)|\(design.version)|" + board
        if let hit = images[key] { return hit }
        if blocked(key) { return nil }
        guard await takeSlot() else { return nil }
        defer { active -= 1 }
        guard ChatThumbAccount.key == account else { return nil }
        do {
            let data = try await client.chatThumbDesignImage(id: design.id, board: board)
            guard !Task.isCancelled, ChatThumbAccount.key == account else { return nil }
            guard let image = UIImage(data: data) else {
                fail(key, permanent: true)
                return nil
            }
            remember(image, key)
            return image
        } catch is CancellationError {
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }
            // A 404 is the desktop saying it has no picture of this version; anything else is asked again later.
            var missing = false
            if let api = error as? APIError, case .server(let status, _) = api, status == 404 { missing = true }
            fail(key, permanent: missing)
            return nil
        }
    }
}

// MARK: - A chat's designs

/// The designs of the chats on screen, read from the desktop: when a chat opens or finishes a turn, and when the
/// desktop's live stream says a design changed. One read per chat at a time and at least 2.5 seconds between two,
/// so a burst of board edits is one read, never a poll.
@Observable
final class ChatThumbDesigns {
    static let shared = ChatThumbDesigns()

    /// Each chat's designs, by the chat's id (a model chat's id, or a bot conversation's).
    private(set) var lists: [String: [ChatThumbDesign]] = [:]
    /// The chats whose list was read at least once.
    private(set) var loadedChats: Set<String> = []
    /// Designs a message named that the chat's list did not hold, read one by one.
    private(set) var known: [String: ChatThumbDesign] = [:]
    /// Designs the desktop no longer has (or this account may not see).
    private(set) var gone: Set<String> = []
    /// Goes up whenever a list changes, so a placement worked out before is worked out again.
    private(set) var stamp = 0

    @ObservationIgnored private var account: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var reading: Set<String> = []
    @ObservationIgnored private var again: Set<String> = []
    @ObservationIgnored private var lastRead: [String: Date] = [:]
    @ObservationIgnored private var trailing: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var watching: Set<String> = []
    @ObservationIgnored private var detailReading: Set<String> = []

    private static let spacing: TimeInterval = 2.5

    // MARK: Account

    /// Everything read goes. `watching` stays unless the phone changed data source altogether.
    func reset(keepWatching: Bool = false) {
        generation += 1
        for task in trailing.values { task.cancel() }
        trailing = [:]
        reading = []
        again = []
        lastRead = [:]
        detailReading = []
        lists = [:]
        loadedChats = []
        known = [:]
        gone = []
        stamp += 1
        if !keepWatching { watching = [] }
        account = ChatThumbAccount.key
    }

    private func current() -> String? {
        let key = ChatThumbAccount.key
        if account != key { reset(keepWatching: true) }
        return key
    }

    // MARK: Reading

    /// The designs of one chat, as last read.
    func designs(in chat: String) -> [ChatThumbDesign] {
        guard ChatThumbAccount.key != nil, account == ChatThumbAccount.key else { return [] }
        return lists[chat] ?? []
    }

    /// A chat came on screen (or left it): its live design news is wanted (or not).
    func watch(_ chat: String, _ on: Bool) {
        guard current() != nil else { return }
        if on { watching.insert(chat) } else { watching.remove(chat) }
    }

    /// Read the chat's designs again, now or as soon as two and a half seconds have passed since the last read.
    func refresh(chat: String) {
        guard let account = current(), !chat.isEmpty else { return }
        if reading.contains(chat) {
            again.insert(chat)
            return
        }
        if let last = lastRead[chat] {
            let wait = ChatThumbDesigns.spacing - Date().timeIntervalSince(last)
            if wait > 0 {
                guard trailing[chat] == nil else { return }
                let gen = generation
                trailing[chat] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled, let self, self.generation == gen else { return }
                    self.trailing[chat] = nil
                    self.refresh(chat: chat)
                }
                return
            }
        }
        reading.insert(chat)
        lastRead[chat] = Date()
        let gen = generation
        Task { await read(chat, account: account, generation: gen) }
    }

    private func read(_ chat: String, account: String, generation gen: Int) async {
        var rows: [ChatThumbDesign]?
        if let client = Connection.shared.client {
            // A failed read is not an error to show: the cards stay as they were. It never touches the connection.
            rows = try? await client.chatThumbDesigns(chat: chat)
        }
        guard generation == gen, ChatThumbAccount.key == account else { return }
        reading.remove(chat)
        if let rows {
            if lists[chat] != rows {
                lists[chat] = rows
                stamp += 1
            }
            if loadedChats.insert(chat).inserted { stamp += 1 }
        }
        if again.remove(chat) != nil { refresh(chat: chat) }
    }

    /// The live stream said a design changed.
    func changed(chat: String?) {
        guard current() != nil else { return }
        if let chat {
            if watching.contains(chat) { refresh(chat: chat) }
        } else {
            for id in watching { refresh(chat: id) }
        }
    }

    // MARK: A design a message named

    /// The design as the card should show it: the chat's own row, else what was read by its id.
    func merged(_ design: ChatThumbDesign) -> ChatThumbDesign {
        design.listed ? design : (known[design.id] ?? design)
    }

    /// Read one design the chat's list did not hold. A 404 means it is gone.
    func loadDetail(_ id: String) async {
        guard let account = current(), let client = Connection.shared.client, ChatThumbWire.isDesignID(id),
              known[id] == nil, !gone.contains(id), !detailReading.contains(id) else { return }
        detailReading.insert(id)
        let gen = generation
        var found: ChatThumbDesign?
        var missing = false
        do {
            found = try await client.chatThumbDesignOne(id)
        } catch {
            if let api = error as? APIError, case .server(let status, _) = api, status == 404 { missing = true }
        }
        guard generation == gen, ChatThumbAccount.key == account else { return }
        detailReading.remove(id)
        if let found {
            known[id] = found
        } else if missing {
            gone.insert(id)
        }
    }
}

// MARK: - The card

/// The design cards under one reply.
struct ChatThumbCards: View {
    let designs: [ChatThumbDesign]
    let chat: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(designs) { design in
                ChatThumbDesignCard(design: design, chat: chat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A design made in a chat: its first board as a picture (a drawn card until it arrives), its name and its size.
/// A tap opens the design in a full-screen cover, the same screen Make opens.
struct ChatThumbDesignCard: View {
    let design: ChatThumbDesign
    let chat: String

    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var image: UIImage?
    @State private var shown = false
    @State private var onScreen = false

    private var store: ChatThumbDesigns { ChatThumbDesigns.shared }
    private var current: ChatThumbDesign { store.merged(design) }
    private var gone: Bool { store.gone.contains(design.id) }

    private var detail: String {
        if gone { return "Design · no longer available" }
        let count = current.boardCount
        if count > 0 { return "Design · \(count) \(count == 1 ? "board" : "boards") · Open" }
        return "Design · Open"
    }

    var body: some View {
        Button {
            Haptics.tap()
            shown = true
        } label: {
            HStack(spacing: 12) {
                picture
                    .frame(width: 84, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title)
                        .font(KFont.ui(15.5, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkDim)
                    .padding(.trailing, 6)
            }
            .padding(8)
            .frame(maxWidth: 340, minHeight: 78, alignment: .leading)
            .kCard(radius: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(gone)
        .opacity(gone ? 0.6 : 1)
        .accessibilityLabel("Open design \(current.title)")
        .onScrollVisibilityChange(threshold: 0.1) { onScreen = $0 }
        .task(id: "\(design.id)|\(current.version)|\(current.firstBoard ?? "")|\(store.loadedChats.contains(chat))|\(onScreen)") {
            guard onScreen else { return }
            // A design a message named that the chat's list does not hold: read it by its own id, once the list is in.
            if !current.listed, store.loadedChats.contains(chat), store.known[design.id] == nil, !gone {
                await store.loadDetail(design.id)
                return
            }
            guard !gone, let picture = await ChatThumbLive.shared.designImage(current) else { return }
            image = picture
        }
        .fullScreenCover(isPresented: $shown) {
            ChatThumbDesignCover(designID: design.id)
                .environment(router)
                .environment(chrome)
        }
    }

    @ViewBuilder
    private var picture: some View {
        if let image {
            ZStack {
                Color(hex: 0xF4F1EC)
                Image(uiImage: image).resizable().scaledToFill()
            }
        } else {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x2E3A44), Color(hex: 0x1D252C)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Palette.goldHi).frame(width: 34, height: 6)
                    Capsule().fill(Palette.cream.opacity(0.3)).frame(width: 52, height: 5)
                    Capsule().fill(Palette.cream.opacity(0.2)).frame(width: 40, height: 5)
                    Capsule().fill(Palette.goldHi.opacity(0.85)).frame(width: 24, height: 11).padding(.top, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(10)
            }
        }
    }
}

/// The real design, full screen, in the same cover Make puts a design in. Its store and toasts are made only when it opens.
private struct ChatThumbDesignCover: View {
    let designID: String
    @State private var store = MakeStore()
    @State private var toast = MakeToast()

    var body: some View {
        MakeCover(start: .design(designID), store: store, toast: toast)
    }
}
