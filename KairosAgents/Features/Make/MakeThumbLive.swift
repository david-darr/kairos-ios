import SwiftUI
import UIKit

// The real pictures of designs and videos on Make (Net/MakeThumbAPI.swift says which routes). Pictures are the
// person's own work: they live in memory only, in a small cache keyed by account and by the item with its last
// change, and are dropped when another desktop or account is paired or the phone is unpaired. A picture that cannot
// be had (the desktop answers 404, or does not answer) is never an error on a card: the card keeps its drawing. A
// failed picture does not touch the connection's state either.

/// How one picture read ended.
enum MakeThumbResult {
    case image(UIImage)
    /// A design the desktop could not draw a picture of just now.
    case missing
    /// A video the desktop has no finished render of, for any of its aspects.
    case notRendered
    /// The desktop did not answer, or sent something that is not a picture.
    case failed
    /// Nobody is waiting for it any more, or another account is showing. Never drawn, never kept.
    case cancelled
}

/// One read that several cards may wait on. It stops when the last card that waits on it leaves.
final class MakeThumbFlight {
    let id: Int
    var task: Task<MakeThumbResult, Never>?
    var watchers = 0

    init(id: Int) { self.id = id }
}

/// One card's place in a flight, so it leaves exactly once.
final class MakeThumbTicket {
    var released = false
}

final class MakeThumbLive {
    static let shared = MakeThumbLive()

    private static let slotCount = 3
    private static let imageLimit = 60
    private static let missSeconds: TimeInterval = 60
    private static let failSeconds: TimeInterval = 15
    private static let sizeLimit = 6_000_000
    /// The long side a picture is shrunk to, and the most decoded memory all kept pictures may hold together.
    private static let longSide: CGFloat = 480
    private static let costLimit = 24_000_000

    private var account = "sample"
    private var images: [String: UIImage] = [:]
    private var imageOrder: [String] = []
    private var imageCosts: [String: Int] = [:]
    private var imageCost = 0

    init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.dropImages() }
        }
    }

    /// Let go of the kept pictures only (a memory warning). They are read again when a card asks.
    private func dropImages() {
        images = [:]
        imageOrder = []
        imageCosts = [:]
        imageCost = 0
    }
    private var misses: [String: (result: MakeThumbResult, until: Date)] = [:]
    private var flights: [String: MakeThumbFlight] = [:]
    private var flightSerial = 0
    private var running = 0
    private var queue: [CheckedContinuation<Void, Never>] = []

    // MARK: Which account

    /// Drop everything when another desktop or account is showing. Answers the account to work for, or nil
    /// when the phone is not paired.
    private func follow() -> String? {
        let now = MakeHomeLive.accountKey
        if now != account {
            clear()
            account = now
        }
        return now == "sample" ? nil : now
    }

    private func stillLive(_ key: String) -> Bool {
        key != "sample" && account == key && MakeHomeLive.accountKey == key
    }

    /// Forget every picture and stop every read. Called when the account changes and when the phone unpairs.
    func clear() {
        for flight in flights.values { flight.task?.cancel() }
        flights = [:]
        dropImages()
        misses = [:]
        account = "sample"
    }

    // MARK: What is already known

    /// What this phone already has for a source, without asking the desktop.
    func known(_ source: MakeThumbSource) -> MakeThumbResult? {
        guard follow() != nil else { return nil }
        return lookup(source.key)
    }

    private func lookup(_ key: String) -> MakeThumbResult? {
        if let image = images[key] { return .image(image) }
        if let miss = misses[key] {
            if miss.until > Date() { return miss.result }
            misses[key] = nil
        }
        return nil
    }

    private func remember(_ key: String, _ answer: MakeThumbResult) {
        switch answer {
        case .image(let image):
            let cost = max(1, (image.cgImage.map { $0.width * $0.height } ?? Int(image.size.width * image.size.height)) * 4)
            imageCost -= imageCosts[key] ?? 0
            images[key] = image
            imageCosts[key] = cost
            imageCost += cost
            imageOrder.removeAll { $0 == key }
            imageOrder.append(key)
            while imageOrder.count > 1, imageOrder.count > Self.imageLimit || imageCost > Self.costLimit {
                let oldest = imageOrder.removeFirst()
                images[oldest] = nil
                imageCost -= imageCosts.removeValue(forKey: oldest) ?? 0
            }
        case .missing, .notRendered:
            misses[key] = (answer, Date().addingTimeInterval(Self.missSeconds))
        case .failed:
            misses[key] = (answer, Date().addingTimeInterval(Self.failSeconds))
        case .cancelled:
            break
        }
        if misses.count > 400 { misses = misses.filter { $0.value.until > Date() } }
    }

    // MARK: Asking

    /// The picture of one source. A few are asked for at a time; asking again for the same source while it is on its
    /// way joins that read; the read stops when every card waiting on it has gone.
    func result(_ source: MakeThumbSource) async -> MakeThumbResult {
        guard let key = follow() else { return .cancelled }
        let name = source.key
        if let kept = lookup(name) { return kept }
        let flight: MakeThumbFlight
        if let running = flights[name] {
            flight = running
        } else {
            flightSerial += 1
            flight = MakeThumbFlight(id: flightSerial)
            flights[name] = flight
            flight.task = Task { [weak self] () -> MakeThumbResult in
                guard let self else { return .cancelled }
                let answer = await self.read(source, account: key)
                self.finish(name, flight, answer, account: key)
                return answer
            }
        }
        flight.watchers += 1
        let ticket = MakeThumbTicket()
        guard let task = flight.task else {
            leave(name, flight, ticket)
            return .cancelled
        }
        let answer = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in self.leave(name, flight, ticket) }
        }
        leave(name, flight, ticket)
        return answer
    }

    private func leave(_ name: String, _ flight: MakeThumbFlight, _ ticket: MakeThumbTicket) {
        guard !ticket.released else { return }
        ticket.released = true
        flight.watchers -= 1
        if flight.watchers <= 0, flights[name] === flight {
            flights[name] = nil
            flight.task?.cancel()
        }
    }

    private func finish(_ name: String, _ flight: MakeThumbFlight, _ answer: MakeThumbResult, account key: String) {
        if flights[name] === flight { flights[name] = nil }
        guard stillLive(key) else { return }
        remember(name, answer)
    }

    // MARK: The reads

    private func acquire() async {
        if running < Self.slotCount {
            running += 1
            return
        }
        await withCheckedContinuation { queue.append($0) }
    }

    private func releaseSlot() {
        if queue.isEmpty {
            running -= 1
        } else {
            queue.removeFirst().resume()
        }
    }

    private func read(_ source: MakeThumbSource, account key: String) async -> MakeThumbResult {
        await acquire()
        defer { releaseSlot() }
        guard !Task.isCancelled, stillLive(key), let client = Connection.shared.client else { return .cancelled }
        switch source.kind {
        case .design(let board):
            guard let path = try? MakeThumbWire.designPath(id: source.id, board: board) else { return .missing }
            return await fetch([path], client: client, account: key, video: false)
        case .video(let aspects):
            let paths = MakeThumbWire.videoPaths(id: source.id, aspects: aspects)
            guard !paths.isEmpty else { return .failed }
            return await fetch(paths, client: client, account: key, video: true)
        }
    }

    /// Ask for each path in turn and stop at the first picture. Only a 404 for every path means there is none;
    /// any other failure is just "no picture now". Nothing here is reported to the connection.
    private func fetch(_ paths: [String], client: APIClient, account key: String, video: Bool) async -> MakeThumbResult {
        var failed = false
        for path in paths {
            guard !Task.isCancelled, stillLive(key) else { return .cancelled }
            do {
                let data = try await client.makeThumbBytes(path)
                guard !Task.isCancelled, stillLive(key) else { return .cancelled }
                if data.count <= Self.sizeLimit {
                    // Decoded and shrunk off the main thread, never held at full size.
                    let size = Self.longSide
                    let picture = await Task.detached { DocsLiveDecode.picture(data, maxPixels: size) }.value
                    guard !Task.isCancelled, stillLive(key) else { return .cancelled }
                    if let picture { return .image(UIImage(cgImage: picture.image)) }
                }
                failed = true
            } catch is CancellationError {
                return .cancelled
            } catch {
                if case .server(let status, _) = error as? APIError, status == 404 { continue }
                failed = true
            }
        }
        if failed { return .failed }
        return video ? .notRendered : .missing
    }
}

// MARK: - Views

/// The picture of a made thing. Not paired, or nothing to fetch for it: exactly the drawing it has always had.
struct MakeThumbArt: View {
    let item: MakeItem
    /// The small picture of a list row.
    var compact = false

    private let home = MakeHomeLive.shared

    var body: some View {
        if MakeHomeLive.paired, home.showing, let source = home.thumbSources[item.id] {
            MakeThumbPicture(item: item, source: source, compact: compact)
        } else {
            MadeArt(item: item)
        }
    }
}

/// A real picture while the desktop has one; a neutral square while it loads; the drawing when it has none.
struct MakeThumbPicture: View {
    let item: MakeItem
    let source: MakeThumbSource
    let compact: Bool

    @State private var result: MakeThumbResult?

    init(item: MakeItem, source: MakeThumbSource, compact: Bool) {
        self.item = item
        self.source = source
        self.compact = compact
        _result = State(initialValue: MakeThumbLive.shared.known(source))
    }

    var body: some View {
        ZStack {
            switch result {
            case .some(.image(let image)):
                picture(image)
            case .some(.notRendered):
                MadeArt(item: item)
                notRenderedLabel
            case .some(.missing), .some(.failed), .some(.cancelled):
                MadeArt(item: item)
            case nil:
                Palette.surface2
            }
        }
        .task(id: MakeHomeLive.accountKey + "|" + source.key) {
            let kept = MakeThumbLive.shared.known(source)
            // Keep the previous picture on screen while a changed item's new one is on its way.
            if kept != nil { result = kept }
            guard kept == nil else { return }
            let answer = await MakeThumbLive.shared.result(source)
            guard !Task.isCancelled else { return }
            if case .cancelled = answer {
                if result == nil { result = .failed }
                return
            }
            result = answer
        }
        .accessibilityHidden(true)
    }

    private func picture(_ image: UIImage) -> some View {
        ZStack {
            if source.isVideo { Color(hex: 0x241A14) } else { Palette.surface2 }
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(source.isVideo ? 0 : (compact ? 3 : 6))
            if source.isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: compact ? 10 : 15, weight: .bold))
                    .foregroundStyle(Palette.night)
                    .frame(width: compact ? 24 : 36, height: compact ? 24 : 36)
                    .background(Palette.cream.opacity(0.85), in: Circle())
            }
        }
    }

    private var notRenderedLabel: some View {
        Text("Not rendered yet")
            .font(KFont.ui(compact ? 9.5 : 11.5, .semibold, relativeTo: .caption2))
            .foregroundStyle(Palette.cream)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, compact ? 4 : 7)
            .frame(height: compact ? 16 : 20)
            .background(Color.black.opacity(0.55), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(compact ? 3 : 8)
    }
}
