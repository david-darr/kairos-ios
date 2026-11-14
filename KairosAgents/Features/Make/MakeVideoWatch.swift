import SwiftUI
import AVKit
import AVFoundation
import WebKit

// The paired editor's two real pictures of a video, both from the person's own desktop:
//
// 1. The preview at the top of the editor is the desktop's own motion player (GET /api/videos/{id}/player), drawn by the
//    phone's web view for the SAVED version. The phone token never reaches the page: the web view loads a private
//    address scheme, and `MakeVideoSchemeHandler` fetches each page, script, font and picture the player asks for
//    through the app's signed client (Net/MakeVideoAPI.swift), only for the few paths `MakeVideoWebPaths` allows.
//    The editor's transport drives the player: each playhead move draws that frame (`window.kdDrawFrame`).
// 2. A finished render is downloaded through the same client to ONE temporary file with real progress, played by the
//    system player and offered to the system share sheet (Save Video, Save to Files). The file is deleted when the
//    player closes, the editor closes, the account changes or the phone unpairs, and stale ones at the next launch.

// MARK: - The temporary files

nonisolated enum MakeVideoWatchFiles {
    private static var cleared = false

    static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("MakeVideoWatch", isDirectory: true) }

    /// Anything a past launch left behind. Runs once per launch, before this launch has made any file.
    static func clearStale() {
        guard !cleared else { return }
        cleared = true
        clearAll()
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// A new folder for one download, left out of backups.
    static func newFolder() throws -> URL {
        var folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        return folder
    }

    static func remove(folder: URL) {
        guard folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}

// MARK: - The download

/// One file from the desktop to one file on the phone, with real progress. A cancelled download is a
/// `CancellationError`, never a failure. The request comes from the app's client, so the token is in its header only.
nonisolated final class MakeVideoFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var destination: URL?
    private var response: HTTPURLResponse?
    private var refusal = Data()
    private var received: Int64 = 0
    private var expected: Int64 = -1
    private var cancelled = false
    private var failure: Error?
    private var lastReport = Date.distantPast
    private var progress: (@Sendable (Int64, Int64) -> Void)?

    func run(_ request: URLRequest, to destination: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                self.destination = destination
                self.progress = progress
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 60 * 60
                configuration.waitsForConnectivity = false
                configuration.httpCookieStorage = nil
                configuration.httpShouldSetCookies = false
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let made = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                let started = made.dataTask(with: request)
                session = made
                task = started
                lock.unlock()
                started.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let current = task
        lock.unlock()
        current?.cancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let http = response as? HTTPURLResponse
        self.response = http
        expected = response.expectedContentLength
        var allow = http != nil
        if let http, (200..<300).contains(http.statusCode), let destination {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            handle = try? FileHandle(forWritingTo: destination)
            if handle == nil {
                failure = APIError.offline("The video could not be saved on this iPhone. Free some space and try again.")
                allow = false
            }
        }
        let total = expected
        let report = progress
        let wrote = handle != nil
        lock.unlock()
        if wrote { report?(0, total) }
        completionHandler(allow ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let handle else {
            if refusal.count < 65_536 { refusal.append(data.prefix(65_536 - refusal.count)) }
            lock.unlock()
            return
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            if failure == nil { failure = APIError.offline("The video could not be saved on this iPhone. Free some space and try again.") }
            lock.unlock()
            dataTask.cancel()
            return
        }
        received += Int64(data.count)
        let now = Date()
        let due = now.timeIntervalSince(lastReport) >= 0.15
        if due { lastReport = now }
        let count = received
        let total = expected
        let report = progress
        lock.unlock()
        if due { report?(count, total) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        try? handle?.close()
        handle = nil
        let waiting = continuation
        continuation = nil
        let http = response
        let body = refusal
        let got = received
        let want = expected
        let writeProblem = failure
        let wasCancelled = cancelled
        let report = progress
        lock.unlock()
        session.finishTasksAndInvalidate()

        var outcome: Error?
        if let writeProblem {
            outcome = writeProblem
        } else if let error {
            if wasCancelled || (error as? URLError)?.code == .cancelled {
                outcome = CancellationError()
            } else if let url = error as? URLError {
                outcome = APIError.from(url)
            } else {
                outcome = APIError.offline("Your desktop could not be reached. Try again in a moment.")
            }
        } else if let http {
            if !(200..<300).contains(http.statusCode) {
                do {
                    try APIClient.check(http, body: body)
                } catch {
                    outcome = error
                }
                if outcome == nil { outcome = APIError.server(status: http.statusCode, detail: "") }
            } else {
                let encoded = (http.value(forHTTPHeaderField: "Content-Encoding") ?? "identity").lowercased() != "identity"
                if got == 0 {
                    outcome = APIError.offline("The video came back empty. Try again.")
                } else if want > 0, got < want, !encoded {
                    outcome = APIError.offline("The download stopped early. Try again.")
                } else {
                    report?(got, got)
                }
            }
        } else {
            outcome = APIError.offline("Your desktop could not be reached. Try again in a moment.")
        }
        if let outcome {
            waiting?.resume(throwing: outcome)
        } else {
            waiting?.resume()
        }
    }
}

// MARK: - What the editor knows about watching

nonisolated enum MakeVideoWatchPhase: Equatable, Sendable {
    case idle
    case downloading(String)
    /// The file that failed and one plain sentence.
    case failed(String, String)
}

/// The downloaded file the player is showing.
struct MakeVideoLocalFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let folder: URL
    let file: String
    let aspect: String
}

/// One per open editor, owned by the live session: dies with the account it was made for.
@Observable
final class MakeVideoWatch {
    var phase = MakeVideoWatchPhase.idle
    var received: Int64 = 0
    var total: Int64?
    var playing: MakeVideoLocalFile?

    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var generation = 0
    @ObservationIgnored var folders: [URL] = []

    /// A download is running or the player is open: Watch is off for every row.
    var busy: Bool {
        if case .downloading = phase { return true }
        return playing != nil
    }

    var downloading: String? {
        if case .downloading(let file) = phase { return file }
        return nil
    }

    /// Stop a download and delete every file this editor made. The player, if open, closes.
    func discardAll() {
        generation += 1
        task?.cancel()
        task = nil
        phase = .idle
        received = 0
        total = nil
        playing = nil
        for folder in folders { MakeVideoWatchFiles.remove(folder: folder) }
        folders = []
    }

    /// The player closed: its file goes.
    func closePlayer() {
        if let file = playing {
            MakeVideoWatchFiles.remove(folder: file.folder)
            folders.removeAll { $0 == file.folder }
        }
        playing = nil
    }
}

// MARK: - Watching a finished render

extension EditorModel {

    /// The desktop's newest finished MP4 for each aspect, read from its folder listing. Starts nothing.
    func refreshRenders() async {
        guard let live, stillLive(live) else { return }
        do {
            let read = try await liveClient().makeVideoResources(projectID)
            guard stillLive(live) else { return }
            live.renders = read.latestRenders()
        } catch {
            // The list stays as it was: this read is only a convenience, and Studio may be off.
        }
    }

    /// A render finished while the editor was open: it is offered at once, then the desktop's listing confirms it.
    func noteRenderReady(_ job: MakeVideoJobDTO) {
        guard let live, stillLive(live), let item = MakeVideoRenderFile(job: job) else { return }
        if let old = live.renders.first(where: { $0.aspect == item.aspect }) {
            if old.number > item.number { return }
            live.renders.removeAll { $0.aspect == item.aspect }
        }
        live.renders.append(item)
        let order = MakeVideoWire.renderSlugs.map(\.aspect)
        live.renders.sort { (order.firstIndex(of: $0.aspect) ?? 9) < (order.firstIndex(of: $1.aspect) ?? 9) }
        Task { await self.refreshRenders() }
    }

    /// Download this render to a temporary file, then play it. One at a time.
    func watchRender(_ item: MakeVideoRenderFile) {
        guard let live, stillLive(live), !live.watch.busy else { return }
        let watch = live.watch
        watch.generation += 1
        let mine = watch.generation
        watch.phase = .downloading(item.file)
        watch.received = 0
        watch.total = item.bytes
        watch.task = Task { [weak self, weak live] in
            guard let self, let live else { return }
            await self.runWatch(item, live: live, mine: mine)
        }
    }

    func cancelWatch() {
        guard let live else { return }
        live.watch.discardAll()
    }

    /// The editor is closing (not just covered by the player): a download stops and every file is deleted.
    func leaveWatching() {
        guard let live, live.watch.playing == nil else { return }
        live.watch.discardAll()
    }

    private func runWatch(_ item: MakeVideoRenderFile, live: MakeVideoLive, mine: Int) async {
        let watch = live.watch
        var folder: URL?
        func drop() {
            if let folder {
                MakeVideoWatchFiles.remove(folder: folder)
                watch.folders.removeAll { $0 == folder }
            }
        }
        do {
            let request = try liveClient().makeVideoRenderRequest(projectID, file: item.file)
            let made = try MakeVideoWatchFiles.newFolder()
            folder = made
            watch.folders.append(made)
            let destination = made.appendingPathComponent(item.file)
            let fetch = MakeVideoFetch()
            try await fetch.run(request, to: destination) { count, total in
                Task { @MainActor in
                    guard watch.generation == mine else { return }
                    watch.received = count
                    if total > 0 { watch.total = total }
                }
            }
            // A download from one account is never played under another.
            guard stillLive(live), watch.generation == mine else {
                drop()
                return
            }
            var file = destination
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? file.setResourceValues(values)
            watch.phase = .idle
            watch.task = nil
            watch.playing = MakeVideoLocalFile(url: destination, folder: made, file: item.file, aspect: item.aspect)
            Haptics.success()
        } catch {
            drop()
            if error is CancellationError || Task.isCancelled {
                if watch.generation == mine, stillLive(live) { watch.phase = .idle }
                return
            }
            guard stillLive(live), watch.generation == mine else { return }
            // A failed download is only that: it never marks the phone as unpaired.
            var words = "The video could not be downloaded. " + error.plainWords
            if case .server(let status, _)? = error as? APIError, status == 404 {
                words = "Your desktop no longer has this render. Render it again to watch it."
                Task { await self.refreshRenders() }
            } else if case .unauthorized? = error as? APIError {
                words = "Your desktop did not allow this download. Try again in a moment."
            }
            watch.phase = .failed(item.file, words)
            watch.task = nil
        }
    }
}

// MARK: - The system player

/// A finished render, played by the system player, with the system share sheet for the file.
struct MakeVideoPlayerScreen: View {
    let file: MakeVideoLocalFile
    let onClose: () -> Void
    @State private var player: AVPlayer

    init(file: MakeVideoLocalFile, onClose: @escaping () -> Void) {
        self.file = file
        self.onClose = onClose
        _player = State(initialValue: AVPlayer(url: file.url))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                GlassIconButton(symbol: "xmark", label: "Close the video") { close() }
                Spacer(minLength: 6)
                Text("\(file.aspect) render")
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                Spacer(minLength: 6)
                ShareLink(item: file.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("Save or share the video")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            VideoPlayer(player: player)
            Text("Save Video puts it in Photos. Save to Files keeps it in Files. When you close this, the copy on this iPhone is deleted.")
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .background(Palette.ground.ignoresSafeArea())
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            player.play()
        }
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }

    private func close() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        onClose()
    }
}

// MARK: - The preview: the desktop's own player

nonisolated enum MakeVideoPreviewStatus: Equatable, Sendable {
    case loading, ready
    case failed(String)
}

/// Answers the web view's requests for the player's page, scripts, fonts and pictures from the desktop, through the
/// app's signed client. Anything else is refused. The page never sees the phone token.
final class MakeVideoSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "kairosvideo"
    static let host = "player"

    let videoID: String
    let account: String
    let aspect: String
    let version: Int
    var onPageError: ((String) -> Void)?
    private var jobs: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(videoID: String, account: String, aspect: String, version: Int) {
        self.videoID = videoID
        self.account = account
        self.aspect = aspect
        self.version = version
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask as AnyObject)
        jobs[key] = Task { [weak self] in
            await self?.serve(urlSchemeTask, key: key)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask as AnyObject)
        jobs.removeValue(forKey: key)?.cancel()
    }

    /// The web view is going away: nothing more is fetched or answered.
    func cancelAll() {
        for job in jobs.values { job.cancel() }
        jobs = [:]
    }

    private func serve(_ task: any WKURLSchemeTask, key: ObjectIdentifier) async {
        guard let url = task.request.url, url.scheme == Self.scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.host == Self.host,
              MakeVideoWebPaths.allowed(parts.path, video: videoID) else {
            finish(task, key, status: 404, type: "text/plain", body: Data())
            return
        }
        let path = parts.path
        let isPage = MakeVideoWebPaths.isPlayer(path, video: videoID)
        guard MakeVideoLive.accountKey == account, let client = Connection.shared.client else {
            if isPage { onPageError?("The preview could not load. This iPhone is not connected to the desktop it was opened on.") }
            finish(task, key, status: 404, type: "text/plain", body: Data())
            return
        }
        do {
            let query: [String: String?] = isPage ? ["aspect": aspect, "v": String(version)] : [:]
            let target = try client.makeVideoDesktopURL(path: path, query: query)
            let data = try await client.makeVideoWebFetch(target)
            guard jobs[key] != nil else { return }
            guard MakeVideoLive.accountKey == account else {
                finish(task, key, status: 404, type: "text/plain", body: Data())
                return
            }
            finish(task, key, status: 200, type: MakeVideoWebPaths.mime(path, body: data, video: videoID), body: data)
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            guard jobs[key] != nil else { return }
            if isPage { onPageError?("The preview could not load. " + error.plainWords) }
            finish(task, key, status: 404, type: "text/plain", body: Data())
        }
    }

    /// Answers once, and only a task the web view has not stopped (answering a stopped task is a crash).
    private func finish(_ task: any WKURLSchemeTask, _ key: ObjectIdentifier, status: Int, type: String, body: Data) {
        guard jobs.removeValue(forKey: key) != nil else { return }
        let headers = ["Content-Type": type, "Content-Length": String(body.count), "Cache-Control": "no-store",
                       "Access-Control-Allow-Origin": "*"]
        guard let url = task.request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        if !body.isEmpty { task.didReceive(body) }
        task.didFinish()
    }
}

/// The desktop's motion player for one saved version, in a web view with no stored data. Each time the editor's
/// playhead moves, that frame is drawn (the player's own `kdDrawFrame`).
struct MakeVideoPlayerWebView: UIViewRepresentable {
    let videoID: String
    let account: String
    let aspect: String
    let version: Int
    let time: Double
    let onStatus: (MakeVideoPreviewStatus) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onStatus: onStatus) }

    func makeUIView(context: Context) -> WKWebView {
        let handler = MakeVideoSchemeHandler(videoID: videoID, account: account, aspect: aspect, version: version)
        let coordinator = context.coordinator
        handler.onPageError = { [weak coordinator] text in coordinator?.fail(text) }
        let configuration = WKWebViewConfiguration()
        // Nothing the page loads or keeps is written to disk.
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        configuration.setURLSchemeHandler(handler, forURLScheme: MakeVideoSchemeHandler.scheme)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.dataDetectorTypes = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isUserInteractionEnabled = false
        view.navigationDelegate = coordinator
        coordinator.attach(view, handler: handler)
        coordinator.draw(time)
        if let start = URL(string: "\(MakeVideoSchemeHandler.scheme)://\(MakeVideoSchemeHandler.host)/api/videos/\(videoID)/player") {
            view.load(URLRequest(url: start))
            coordinator.startTimeout()
        } else {
            coordinator.fail("The preview could not load.")
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onStatus = onStatus
        context.coordinator.draw(time)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        view.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onStatus: (MakeVideoPreviewStatus) -> Void
        private weak var view: WKWebView?
        private var handler: MakeVideoSchemeHandler?
        private var ready = false
        private var finished = false
        private var busy = false
        private var want: Double?
        private var lastDrawn: Double?
        private var readyTask: Task<Void, Never>?
        private var timeoutTask: Task<Void, Never>?

        init(onStatus: @escaping (MakeVideoPreviewStatus) -> Void) { self.onStatus = onStatus }

        func attach(_ view: WKWebView, handler: MakeVideoSchemeHandler) {
            self.view = view
            self.handler = handler
        }

        /// A page that never becomes ready is a failure, not a black box.
        func startTimeout() {
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.fail("The preview took too long to draw.")
            }
        }

        func stop() {
            finished = true
            readyTask?.cancel()
            timeoutTask?.cancel()
            handler?.cancelAll()
            handler?.onPageError = nil
        }

        /// The first problem is the one shown.
        func fail(_ text: String) {
            guard !finished else { return }
            finished = true
            ready = false
            readyTask?.cancel()
            timeoutTask?.cancel()
            Task { @MainActor [weak self] in self?.onStatus(.failed(text)) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Only the player's own page loads. A link or a redirect to anywhere else goes nowhere.
            guard let url = navigationAction.request.url, url.scheme == MakeVideoSchemeHandler.scheme,
                  navigationAction.navigationType == .other else { return .cancel }
            return .allow
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished else { return }
            readyTask?.cancel()
            readyTask = Task { [weak self] in await self?.waitReady() }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            fail("The preview could not load.")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            fail("The preview could not load.")
        }

        private func waitReady() async {
            guard let view else { return }
            do {
                _ = try await view.callAsyncJavaScript(
                    "if (!window.kdReady) { throw new Error('The player did not start.'); } await window.kdReady; return true;",
                    arguments: [:], in: nil, contentWorld: .page)
                guard !Task.isCancelled, !finished else { return }
                ready = true
                timeoutTask?.cancel()
                onStatus(.ready)
                draw(want ?? 0)
            } catch {
                if Task.isCancelled { return }
                fail("The preview could not be drawn on this iPhone.")
            }
        }

        /// Draw the frame at this time. One draw at a time; while one runs only the newest request waits.
        func draw(_ time: Double) {
            want = max(0, time)
            guard ready, !busy, let view else { return }
            busy = true
            Task { [weak self] in
                while let self, let next = self.want {
                    self.want = nil
                    if next == self.lastDrawn { continue }
                    _ = try? await view.callAsyncJavaScript(
                        "if (window.kdDrawFrame) { await window.kdDrawFrame(t); } return true;",
                        arguments: ["t": next], in: nil, contentWorld: .page)
                    self.lastDrawn = next
                }
                self?.busy = false
            }
        }
    }
}

/// The picture at the top of the paired editor: the desktop's own player for the saved version. The phone's drawn
/// stand-in is never shown here.
struct EditorLivePreview: View {
    let model: EditorModel
    @State private var status = MakeVideoPreviewStatus.loading
    @State private var attempt = 0

    var body: some View {
        if let live = model.live, let doc = live.doc {
            let aspect = doc.aspects.first ?? "16:9"
            let key = "\(live.account)|\(doc.version)|\(aspect)|\(attempt)"
            VStack(spacing: 10) {
                picture(live: live, doc: doc, aspect: aspect)
                    .onChange(of: key) { status = .loading }
                HintLine(text: note(doc),
                         symbol: model.isDirty ? "exclamationmark.circle" : "info.circle",
                         color: model.isDirty ? Palette.goldText : Palette.inkFaint)
            }
        }
    }

    private func note(_ doc: MakeVideoDoc) -> String {
        if model.isDirty {
            return "This shows the version saved on your desktop (version \(doc.version)). Your unsaved changes are not in it. Save to see them here."
        }
        return "This shows the version saved on your desktop (version \(doc.version))."
    }

    @ViewBuilder private func picture(live: MakeVideoLive, doc: MakeVideoDoc, aspect: String) -> some View {
        let time = min(model.playhead, max(0, live.seconds - 0.02))
        ZStack {
            Color.black
            MakeVideoPlayerWebView(videoID: model.projectID, account: live.account, aspect: aspect, version: doc.version,
                                   time: time) { next in status = next }
                .id("\(live.account)|\(doc.version)|\(aspect)|\(attempt)")
                .allowsHitTesting(false)
            cover
            if model.guides, status == .ready {
                GeometryReader { geo in
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .padding(.horizontal, geo.size.width * 0.05)
                        .padding(.vertical, geo.size.height * 0.08)
                }
                .allowsHitTesting(false)
            }
        }
        .aspectRatio(model.aspectRatio, contentMode: .fit)
        .frame(height: model.aspectRatio < 1 ? 360 : nil)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if status == .ready { model.togglePlay() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of the saved video, at \(EditorFormat.clock(model.playhead))")
    }

    @ViewBuilder private var cover: some View {
        switch status {
        case .loading:
            VStack(spacing: 10) {
                PulsingDot(color: Palette.working)
                Text("Drawing your video with your desktop's player.")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        case .ready:
            EmptyView()
        case .failed(let text):
            VStack(spacing: 12) {
                Text(text)
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                MakePillButton(title: "Try again", symbol: "arrow.clockwise") { attempt += 1 }
                Text("A finished render shows the real video. Tap Render, then Watch.")
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
    }
}
