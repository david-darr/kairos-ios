import SwiftUI

// What Kairos makes, and the jobs that make it. Studio's own data lives in StudioModels.swift.

nonisolated enum MadeKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case video, design, document, deck, sheet, image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: "Video"
        case .design: "Design"
        case .document: "Document"
        case .deck: "Deck"
        case .sheet: "Sheet"
        case .image: "Image"
        }
    }

    var plural: String {
        switch self {
        case .video: "Videos"
        case .design: "Designs"
        case .document: "Documents"
        case .deck: "Decks"
        case .sheet: "Sheets"
        case .image: "Images"
        }
    }

    var symbol: String {
        switch self {
        case .video: "film"
        case .design: "paintpalette"
        case .document: "doc.text"
        case .deck: "rectangle.on.rectangle"
        case .sheet: "tablecells"
        case .image: "photo"
        }
    }

    /// The kinds the describe box offers.
    static let makeable: [MadeKind] = [.video, .design, .document, .deck, .image]

    var looks: [String] {
        switch self {
        case .video: ["Motion type", "Flat 2D explainer", "Glossy 3D mascot", "Blocky voxel 3D"]
        case .design: ["Clean", "Warm editorial", "Bold poster", "Your design system"]
        case .document: ["Plain report", "One-pager", "Letter", "Brief"]
        case .deck: ["Simple", "Pitch", "Workshop"]
        case .sheet: ["Plain table"]
        case .image: ["Photo", "Illustration", "Halftone", "Flat icon"]
        }
    }

    var prompt: String {
        switch self {
        case .video: "A 40 second video about..."
        case .design: "A booking page for..."
        case .document: "A one page plan for..."
        case .deck: "Six slides that explain..."
        case .sheet: "A table of..."
        case .image: "A picture of..."
        }
    }

    var look: ChatDocument.Look {
        switch self {
        case .video, .design, .image: .design
        case .sheet: .sheet
        case .document, .deck: .page
        }
    }

    var fileType: String {
        switch self {
        case .video: "MP4"
        case .design: "HTML"
        case .document: "DOCX"
        case .deck: "PPTX"
        case .sheet: "XLSX"
        case .image: "PNG"
        }
    }

    /// The steps a making job shows while it runs.
    var steps: [String] {
        switch self {
        case .video: ["Writing the script", "Planning the beats", "Narrating", "Rendering frames", "Checking the cut"]
        case .design: ["Reading your request", "Laying out the boards", "Styling", "Checking each board"]
        case .document: ["Reading your request", "Outlining", "Writing", "Checking the facts"]
        case .deck: ["Reading your request", "Outlining the slides", "Building the slides", "Checking the layout"]
        case .sheet: ["Reading your request", "Building the table", "Checking the numbers"]
        case .image: ["Reading your request", "Drawing", "Cleaning up"]
        }
    }
}

nonisolated struct MakeItem: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var kind: MadeKind
    var when: String
    var detail: String
    var size: String
    var fresh = false
    /// Where it came from: a chat, a bot, the Make box.
    var source = "Make"

    var document: ChatDocument {
        ChatDocument(id: id, name: "\(title).\(kind.fileType.lowercased())", label: kind.title, details: [kind.fileType, detail, size], look: kind.look)
    }
}

nonisolated struct MakeJob: Identifiable, Hashable, Sendable {
    enum State: Hashable, Sendable { case running, stopped, done }
    let id: String
    var prompt: String
    var kind: MadeKind
    var look: String
    var step = 0
    var progress: Double = 0
    var state: State = .running
    var resultID: String?

    var title: String {
        let words = prompt.split(separator: " ").prefix(5).joined(separator: " ")
        let cleaned = words.trimmingCharacters(in: .punctuationCharacters)
        if cleaned.isEmpty { return "New \(kind.title.lowercased())" }
        let first = String(cleaned.prefix(1)).uppercased()
        return first + String(cleaned.dropFirst())
    }
}

/// Where Make's data comes from. The sample answers today; the desktop connection replaces it.
protocol MakeProviding {
    func madeItems() -> [MakeItem]
}

nonisolated struct SampleMake: MakeProviding {
    func madeItems() -> [MakeItem] {
        [
            MakeItem(id: "v-ride", title: "Spring ride tips", kind: .video, when: "today", detail: "0:42 · 9:16", size: "18 MB", fresh: true, source: "Content team"),
            MakeItem(id: "v-tube", title: "Fixing a flat in a minute", kind: .video, when: "yesterday", detail: "0:58 · 9:16", size: "24 MB", source: "Content team"),
            MakeItem(id: "v-shop", title: "Inside the shop", kind: .video, when: "last week", detail: "1:30 · 16:9", size: "61 MB"),
            MakeItem(id: "doc-report", title: "Weekly report", kind: .document, when: "today", detail: "2 pages", size: "22 kB", fresh: true, source: "Chat with Kip"),
            MakeItem(id: "doc-plan", title: "Launch plan", kind: .document, when: "yesterday", detail: "1 page", size: "18 kB", source: "Bike shop launch"),
            MakeItem(id: "doc-letter", title: "Letter to the landlord", kind: .document, when: "Mon", detail: "1 page", size: "9 kB"),
            MakeItem(id: "deck-launch", title: "Launch slides", kind: .deck, when: "yesterday", detail: "8 slides", size: "1.2 MB", source: "Bike shop launch"),
            MakeItem(id: "deck-class", title: "Repair class", kind: .deck, when: "last week", detail: "12 slides", size: "2.4 MB"),
            MakeItem(id: "sheet-prices", title: "Rival prices", kind: .sheet, when: "yesterday", detail: "3 rows", size: "14 kB", source: "Bike shop launch"),
            MakeItem(id: "sheet-stock", title: "Stock count", kind: .sheet, when: "Mon", detail: "48 rows", size: "31 kB"),
            MakeItem(id: "img-badge", title: "Shop badge", kind: .image, when: "today", detail: "1024 x 1024", size: "640 kB", fresh: true),
            MakeItem(id: "img-poster", title: "Sale poster art", kind: .image, when: "Tue", detail: "1200 x 1800", size: "1.1 MB"),
        ]
    }
}

/// Everything Make shows. One store for the tab, shared with its full-screen places.
@Observable
final class MakeStore {
    var items: [MakeItem]
    var jobs: [MakeJob] = []
    let studio = StudioStore()
    private var runners: [String: Task<Void, Never>] = [:]

    init(provider: MakeProviding = SampleMake()) {
        items = provider.madeItems()
    }

    func items(_ kind: MadeKind) -> [MakeItem] { items.filter { $0.kind == kind } }

    func item(_ id: String?) -> MakeItem? { items.first { $0.id == id } }

    /// Start making something. The job walks its steps and ends in a result.
    @discardableResult
    func start(prompt: String, kind: MadeKind, look: String) -> String {
        let job = MakeJob(id: UUID().uuidString, prompt: prompt, kind: kind, look: look)
        withAnimation(Motion.bouncy) { jobs.insert(job, at: 0) }
        run(job.id)
        return job.id
    }

    func stop(_ id: String) {
        runners[id]?.cancel()
        runners[id] = nil
        update(id) { $0.state = .stopped }
    }

    func resume(_ id: String) {
        update(id) { $0.state = .running }
        run(id)
    }

    func dismiss(_ id: String) {
        runners[id]?.cancel()
        runners[id] = nil
        withAnimation(Motion.snappy) { jobs.removeAll { $0.id == id } }
    }

    /// Debug pictures: a job part way through, or finished.
    func seedJob(done: Bool) {
        var job = MakeJob(id: "seed", prompt: "A booking page for the bike shop with prices", kind: .design, look: "Warm editorial")
        if done {
            job.step = job.kind.steps.count - 1
            job.progress = 1
            job.state = .done
            let item = MakeItem(id: "made-seed", title: job.title, kind: .design, when: "just now", detail: "3 boards", size: "48 kB", fresh: true)
            items.insert(item, at: 0)
            job.resultID = item.id
        } else {
            job.step = 2
            job.progress = 0.58
        }
        jobs = [job]
    }

    private func run(_ id: String) {
        runners[id]?.cancel()
        runners[id] = Task { [weak self] in
            while let self, let job = self.jobs.first(where: { $0.id == id }), job.state == .running {
                try? await Task.sleep(for: .milliseconds(140))
                if Task.isCancelled { return }
                self.update(id) { job in
                    job.progress = min(1, job.progress + 0.022)
                    let count = Double(job.kind.steps.count)
                    job.step = min(job.kind.steps.count - 1, Int(job.progress * count))
                }
                if let current = self.jobs.first(where: { $0.id == id }), current.progress >= 1 {
                    self.finish(id)
                    return
                }
            }
        }
    }

    private func finish(_ id: String) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        let detail: String
        switch job.kind {
        case .video: detail = "0:40 · 9:16"
        case .design: detail = "3 boards"
        case .document: detail = "1 page"
        case .deck: detail = "6 slides"
        case .sheet: detail = "12 rows"
        case .image: detail = "1024 x 1024"
        }
        let item = MakeItem(id: "made-\(id)", title: job.title, kind: job.kind, when: "just now", detail: detail, size: job.kind == .video ? "17 MB" : "36 kB", fresh: true)
        withAnimation(Motion.bouncy) {
            items.insert(item, at: 0)
            update(id) {
                $0.state = .done
                $0.resultID = item.id
            }
        }
        runners[id] = nil
        Haptics.success()
    }

    private func update(_ id: String, _ change: (inout MakeJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }
}
