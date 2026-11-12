import SwiftUI

// The video editor on a phone: a drawn 9:16 preview, transport, a real timeline with beats,
// narration, music, one overlay track, chapters and comment pins, plus the beat and clip
// inspectors, Ask Kairos and Render. Everything runs on made-up sample data.

// MARK: - Entry points

nonisolated enum VideoEditorStart: Hashable, Sendable { case timeline, inspector, render, ask }

enum VideoEditorDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "editor": return AnyView(VideoEditorScreen(start: .timeline))
        case "editor-inspector": return AnyView(VideoEditorScreen(start: .inspector))
        case "editor-render": return AnyView(VideoEditorScreen(start: .render))
        case "editor-ask": return AnyView(VideoEditorScreen(start: .ask))
        default: return nil
        }
    }
}

struct VideoEditorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MakeToast.self) private var toast
    @State private var model: EditorModel
    private let start: VideoEditorStart

    init(projectID: String = "sample", start: VideoEditorStart = .timeline) {
        self.start = start
        _model = State(initialValue: EditorModel(projectID: projectID))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                EditorPreview(model: model)
                transport
                workArea
                HStack(spacing: 10) {
                    PillButton(title: "Ask Kairos", symbol: "sparkles", expand: true) { model.sheet = .ask }
                    PillButton(title: renderTitle, symbol: "film", filled: true, expand: true) { model.startRender() }
                        .editorEnabled(!model.isRendering)
                }
                if model.render != .idle {
                    EditorRenderCard(model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                EditorTimeline(model: model)
                EditorTrackRow(model: model)
                EditorSelectionPanel(model: model)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 40)
            .animation(Motion.snappy, value: model.render == .idle)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top) { header }
        .kScreen()
        .sheet(item: $model.sheet) { sheet in
            EditorSheetHost(model: model, sheet: sheet)
        }
        .task { await boot() }
        .onDisappear { model.pause() }
    }

    private var renderTitle: String {
        switch model.render {
        case .running: return "Rendering"
        case .done: return "Render again"
        default: return "Render"
        }
    }

    private var header: some View {
        MakeHeader(title: model.title, subtitle: "\(EditorFormat.clock(model.total)), 9:16, 30 fps", back: { dismiss() }) {
            GlassIconButton(symbol: "arrow.uturn.backward", label: "Undo") { model.undo() }
                .editorEnabled(model.canUndo)
            GlassIconButton(symbol: "arrow.uturn.forward", label: "Redo") { model.redo() }
                .editorEnabled(model.canRedo)
        }
    }

    private var transport: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                GlassIconButton(symbol: "backward.end.fill", label: "Previous beat edge") { model.jumpEdge(forward: false) }
                GlassIconButton(symbol: "backward.frame.fill", label: "Back one frame") { model.step(frames: -1) }
                Button {
                    Haptics.tap()
                    model.togglePlay()
                } label: {
                    Image(systemName: model.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.onGold)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 60, height: 60)
                        .background(Palette.gold, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle(scale: 0.92))
                .accessibilityLabel(model.playing ? "Pause" : "Play")
                GlassIconButton(symbol: "forward.frame.fill", label: "Forward one frame") { model.step(frames: 1) }
                GlassIconButton(symbol: "forward.end.fill", label: "Next beat edge") { model.jumpEdge(forward: true) }
            }
            HStack(spacing: 8) {
                Text(EditorFormat.timecode(model.playhead))
                    .font(KFont.ui(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                Text("of \(EditorFormat.timecode(model.total))")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .monospacedDigit()
                Spacer(minLength: 4)
                EditorTogglePill(title: "Guides", isOn: model.guides) { model.guides.toggle() }
            }
        }
    }

    private var workArea: some View {
        HStack(spacing: 8) {
            PillButton(title: "In") { model.setIn() }
            PillButton(title: "Out") { model.setOut() }
            if model.workIn != nil || model.workOut != nil {
                PillButton(title: "Clear") { model.clearWork() }
            }
            Text(model.workText)
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func boot() async {
        model.toast = toast
        guard !model.booted else { return }
        model.booted = true
        guard let first = model.state.beats.first?.id else { return }
        switch start {
        case .timeline:
            break
        case .inspector:
            model.selection = .beat(first)
            try? await Task.sleep(for: .milliseconds(350))
            model.sheet = .beat(first)
        case .render:
            model.playhead = 12
            model.startRender(from: 0.38, rate: 0.0015)
        case .ask:
            model.selection = .beat(first)
            try? await Task.sleep(for: .milliseconds(350))
            model.sheet = .ask
        }
    }
}

// MARK: - Data

nonisolated enum EditorBeatKind: String, Hashable, Sendable {
    case scene, story, stage, blocky

    var title: String {
        switch self {
        case .scene: "Scene"
        case .story: "Story"
        case .stage: "3D stage"
        case .blocky: "Blocky world"
        }
    }
}

nonisolated struct EditorCharacter: Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var position: Double
    var expression = "neutral"
    var action = "idle"
    var speaks = false
}

nonisolated struct EditorProp: Identifiable, Hashable, Sendable {
    var id: Int
    var icon: String
    var across: Double
    var size: Double
    var floats = false
}

nonisolated struct EditorBeat: Identifiable, Hashable, Sendable {
    static let secondsPerBar = 2.0
    static let placeholder = EditorBeat(id: -1, kind: .scene, caption: "", narrated: false, seconds: 2, bars: 1)

    var id: Int
    var kind: EditorBeatKind
    var caption: String
    var narrated: Bool
    var seconds: Double
    var bars: Double
    var setting = "meadow"
    var shot = "medium"
    var characters: [EditorCharacter] = []
    var props: [EditorProp] = []
    var speaker = "Rook"
    var gap = 0.4
    var flashback = false
    var keyWords = ""
    var place = "meadow"
    var timeOfDay = "day"
    var shots: [String] = ["medium"]
    var world = "meadow"
    var pedestal = false

    var length: Double { narrated ? seconds : bars * Self.secondsPerBar }
}

nonisolated enum EditorClipKind: Hashable, Sendable {
    case text, shape
    var title: String { self == .text ? "Text" : "Shape" }
}

nonisolated struct EditorClip: Identifiable, Hashable, Sendable {
    var id: Int
    var kind: EditorClipKind
    var start: Double
    var length: Double
    var text = "Your text"
    var size = "Headline"
    var style = "On a card"
    var colour = "Text"
    var align = "Center"
    var shape = "Rectangle"
    var filled = true
    var fadeIn = 0.0
    var fadeOut = 0.0
    var opacity = 1.0
    var left = 10.0
    var top = 12.0
    var width = 80.0
    var height = 12.0
    var animated: Set<String> = []
    var keyTimes: [Double] = []

    var end: Double { start + length }
    var label: String {
        kind == .text ? (text.isEmpty ? "Empty text" : text) : "\(colour) \(shape.lowercased())"
    }
}

nonisolated struct EditorState: Hashable, Sendable {
    var beats: [EditorBeat]
    var clips: [EditorClip]
    var trackHidden = false
    var trackLocked = false
    var trackRemoved = false
    var nextID = 100
}

nonisolated enum EditorSelection: Hashable, Sendable { case beat(Int), clip(Int) }

nonisolated enum EditorSheet: Hashable, Identifiable, Sendable {
    case beat(Int), clip(Int), ask

    var id: String {
        switch self {
        case .beat(let id): "beat-\(id)"
        case .clip(let id): "clip-\(id)"
        case .ask: "ask"
        }
    }
}

nonisolated enum EditorRender: Hashable, Sendable { case idle, running(Double), stopped(Double), done }
nonisolated enum EditorEdge: Hashable, Sendable { case start, end }

nonisolated struct EditorSpan: Hashable, Sendable {
    var start: Double
    var end: Double
    var seed: Int
}

nonisolated struct EditorMark: Identifiable, Hashable, Sendable {
    var id: Int
    var number: Int
    var title: String
    var time: Double
}

nonisolated struct EditorComment: Identifiable, Hashable, Sendable {
    var id: Int
    var time: Double
    var text: String
}

nonisolated enum EditorOptions {
    static let lockNote = "This track is locked. Unlock it to change its clips."
    static let settings = ["meadow", "city", "space", "room", "ocean", "lab"]
    static let shots = ["wide", "medium", "close"]
    static let cast = ["Pip", "Mara", "Rook"]
    static let expressions = ["neutral", "happy", "surprised", "worried", "thinking"]
    static let actions = ["idle", "wave", "point", "walk", "jump", "shrug", "think", "nod"]
    static let icons = ["sun", "moon", "star", "cloud", "lightbulb", "heart", "book", "planet", "drop", "leaf",
                        "gear", "arrow", "question", "coin", "clock", "rocket", "tree", "house", "magnifier", "atom"]
    static let speakers = ["Rook", "Pip Block", "Mara"]
    static let places = ["meadow", "cliff", "village", "party", "cave", "beach", "sky-island"]
    static let storyTimes = ["day", "dusk"]
    static let storyShots = ["close", "medium", "wide", "low", "top", "orbit"]
    static let stageSets = ["lavender", "peach", "mint", "sky", "night"]
    static let worlds = ["meadow", "cave", "village", "sky-island", "ocean"]
    static let worldTimes = ["day", "dusk", "night"]
    static let colours = ["Text", "Soft text", "Accent", "Second accent", "Background", "Surface", "White", "Black"]
    static let shapes = ["Rectangle", "Ellipse", "Line", "Arrow"]
    static let keyNames = ["Left", "Top", "Size", "Turn", "Opacity"]
}

nonisolated enum EditorSample {
    static var state: EditorState {
        var b1 = EditorBeat(id: 1, kind: .scene, caption: "Spring is here, and the trails are calling.", narrated: true, seconds: 6.4, bars: 3)
        b1.setting = "meadow"
        b1.shot = "wide"
        b1.characters = [
            EditorCharacter(id: 1, name: "Pip", position: 32, expression: "happy", speaks: true),
            EditorCharacter(id: 2, name: "Mara", position: 70, action: "wave"),
        ]
        b1.props = [EditorProp(id: 1, icon: "sun", across: 78, size: 12, floats: true)]

        var b2 = EditorBeat(id: 2, kind: .story, caption: "Rook checks the old bike and frowns.", narrated: true, seconds: 5.2, bars: 3)
        b2.speaker = "Rook"
        b2.keyWords = "bike, frowns"
        b2.place = "village"
        b2.shots = ["medium", "close"]

        var b3 = EditorBeat(id: 3, kind: .scene, caption: "Main street at golden hour.", narrated: false, seconds: 8, bars: 4)
        b3.setting = "city"
        b3.characters = [EditorCharacter(id: 1, name: "Pip", position: 50, action: "walk")]
        b3.props = [EditorProp(id: 1, icon: "house", across: 22, size: 14), EditorProp(id: 2, icon: "star", across: 80, size: 8, floats: true)]

        var b4 = EditorBeat(id: 4, kind: .stage, caption: "A full tune-up in under an hour.", narrated: true, seconds: 7.0, bars: 3)
        b4.world = "mint"
        b4.pedestal = true

        var b5 = EditorBeat(id: 5, kind: .blocky, caption: "A blocky ride through the village.", narrated: false, seconds: 6, bars: 3)
        b5.world = "village"
        b5.timeOfDay = "dusk"
        b5.shot = "wide"

        var b6 = EditorBeat(id: 6, kind: .scene, caption: "Come by the shop this weekend. Spring prices end Friday.", narrated: true, seconds: 9.4, bars: 4)
        b6.setting = "room"
        b6.shot = "close"
        b6.characters = [EditorCharacter(id: 1, name: "Mara", position: 50, expression: "happy", action: "point", speaks: true)]
        b6.props = [EditorProp(id: 1, icon: "coin", across: 20, size: 10)]

        let clips = [
            EditorClip(id: 50, kind: .text, start: 0.5, length: 3, text: "Spring ride", fadeIn: 0.3, fadeOut: 0.3, top: 10),
            EditorClip(id: 51, kind: .shape, start: 14, length: 4, colour: "Accent", shape: "Ellipse", filled: false,
                       left: 30, top: 30, width: 40, height: 22),
            EditorClip(id: 52, kind: .text, start: 34, length: 5, text: "Open till 6 pm", size: "Body", style: "Plain", top: 74),
        ]
        return EditorState(beats: [b1, b2, b3, b4, b5, b6], clips: clips)
    }
}

// MARK: - Model

@Observable
final class EditorModel {
    let projectID: String
    let title = "Spring ride"
    var state: EditorState
    private(set) var past: [EditorState] = []
    private(set) var future: [EditorState] = []
    var playhead: Double = 0
    var playing = false
    var zoom: Double = 22
    var snap = true
    var ripple = false
    var guides = false
    var workIn: Double?
    var workOut: Double?
    var selection: EditorSelection?
    var sheet: EditorSheet?
    var render: EditorRender = .idle

    @ObservationIgnored var toast: MakeToast?
    @ObservationIgnored var booted = false
    @ObservationIgnored private var lastTag: String?
    @ObservationIgnored private var lastTagTime = Date.distantPast
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var renderRate = 0.012
    @ObservationIgnored private var askCount = 0

    let comments: [EditorComment] = [
        EditorComment(id: 1, time: 3.5, text: "The caption feels long here."),
        EditorComment(id: 2, time: 27, text: "Music could dip lower."),
    ]
    private let chapters: [(beat: Int, title: String)] = [(1, "Opening"), (4, "The offer")]

    init(projectID: String) {
        self.projectID = projectID
        self.state = EditorSample.state
    }

    // Reading

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var total: Double { state.beats.reduce(0) { $0 + $1.length } }

    var starts: [Double] {
        var result: [Double] = []
        var t = 0.0
        for beat in state.beats {
            result.append(t)
            t += beat.length
        }
        return result
    }

    var currentIndex: Int {
        var found = 0
        for (i, start) in starts.enumerated() where playhead >= start - 0.0001 { found = i }
        return found
    }

    var currentBeat: EditorBeat {
        state.beats.isEmpty ? .placeholder : state.beats[min(currentIndex, state.beats.count - 1)]
    }

    func index(of id: Int) -> Int? { state.beats.firstIndex { $0.id == id } }
    func clipIndex(_ id: Int) -> Int? { state.clips.firstIndex { $0.id == id } }

    var selectedBeat: EditorBeat? {
        if case .beat(let id)? = selection { return state.beats.first { $0.id == id } }
        return nil
    }

    var selectedClip: EditorClip? {
        if case .clip(let id)? = selection { return state.clips.first { $0.id == id } }
        return nil
    }

    var workRange: ClosedRange<Double>? {
        guard let a = workIn, let b = workOut, b > a else { return nil }
        return a...b
    }

    var workText: String {
        if let range = workRange {
            return "Loops \(EditorFormat.timecode(range.lowerBound)) to \(EditorFormat.timecode(range.upperBound))"
        }
        if let a = workIn { return "In at \(EditorFormat.timecode(a)). Set Out to loop." }
        if let b = workOut { return "Out at \(EditorFormat.timecode(b)). Set In to loop." }
        return "No work area. In and Out set one."
    }

    var rulerStep: Double {
        let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60]
        return steps.first { $0 * zoom >= 56 } ?? 60
    }

    var narrationSpans: [EditorSpan] {
        let s = starts
        var spans: [EditorSpan] = []
        for (i, beat) in state.beats.enumerated() where beat.narrated {
            spans.append(EditorSpan(start: s[i], end: s[i] + beat.length, seed: beat.id))
        }
        return spans
    }

    var chapterMarks: [EditorMark] {
        let s = starts
        var marks: [EditorMark] = []
        for chapter in chapters {
            if let i = index(of: chapter.beat) {
                marks.append(EditorMark(id: chapter.beat, number: marks.count + 1, title: chapter.title, time: s[i]))
            }
        }
        return marks
    }

    var activeClips: [EditorClip] {
        if state.trackRemoved || state.trackHidden { return [] }
        return state.clips.filter { playhead >= $0.start && playhead < $0.end }
    }

    func clipOpacity(_ clip: EditorClip) -> Double {
        var f = 1.0
        if clip.fadeIn > 0 { f = min(f, (playhead - clip.start) / clip.fadeIn) }
        if clip.fadeOut > 0 { f = min(f, (clip.end - playhead) / clip.fadeOut) }
        return clip.opacity * min(1, max(0, f))
    }

    var isRendering: Bool {
        if case .running = render { return true }
        return false
    }

    // Undo

    func mutate(_ tag: String? = nil, _ change: (inout EditorState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        let now = Date()
        let coalesce = tag != nil && tag == lastTag && now.timeIntervalSince(lastTagTime) < 0.8
        if !coalesce {
            past.append(state)
            if past.count > 80 { past.removeFirst() }
        }
        lastTag = tag
        lastTagTime = now
        future.removeAll()
        state = next
    }

    func undo() {
        guard let previous = past.popLast() else { return }
        future.append(state)
        state = previous
        lastTag = nil
        playhead = min(playhead, total)
        Haptics.tap()
    }

    func redo() {
        guard let next = future.popLast() else { return }
        past.append(state)
        state = next
        lastTag = nil
        playhead = min(playhead, total)
        Haptics.tap()
    }

    func select(_ item: EditorSelection) { selection = item }

    // Playback

    func togglePlay() { playing ? pause() : play() }

    func play() {
        if workRange == nil, playhead >= total - 0.001 { playhead = 0 }
        playing = true
        playTask?.cancel()
        playTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, self.playing, !Task.isCancelled else { return }
                self.advance(1.0 / 30.0)
            }
        }
    }

    func pause() {
        playing = false
        playTask?.cancel()
        playTask = nil
    }

    private func advance(_ dt: Double) {
        let t = playhead + dt
        if let range = workRange {
            playhead = (t >= range.upperBound || t < range.lowerBound) ? range.lowerBound : t
        } else if t >= total {
            playhead = total
            pause()
        } else {
            playhead = t
        }
    }

    private func frame(_ t: Double) -> Double { (t * 30).rounded() / 30 }

    func step(frames: Int) {
        pause()
        playhead = frame(min(max(0, playhead + Double(frames) / 30), total))
    }

    func jumpEdge(forward: Bool) {
        pause()
        let edges = starts + [total]
        if forward {
            playhead = edges.first { $0 > playhead + 0.001 } ?? total
        } else {
            playhead = edges.last { $0 < playhead - 0.001 } ?? 0
        }
        Haptics.select()
    }

    func scrub(to t: Double) {
        if playing { pause() }
        playhead = snapped(t)
    }

    func seek(_ t: Double) {
        pause()
        playhead = frame(min(max(0, t), total))
    }

    func snapped(_ t: Double) -> Double {
        var value = min(max(0, t), total)
        if snap {
            var targets = starts + [total]
            for clip in state.clips {
                targets.append(clip.start)
                targets.append(clip.end)
            }
            if let a = workIn { targets.append(a) }
            if let b = workOut { targets.append(b) }
            let tolerance = 8 / zoom
            if let best = targets.min(by: { abs($0 - value) < abs($1 - value) }), abs(best - value) <= tolerance {
                value = best
            }
        }
        return frame(value)
    }

    func setIn() {
        let t = frame(playhead)
        workIn = t
        if let out = workOut, out <= t { workOut = nil }
        Haptics.select()
    }

    func setOut() {
        let t = frame(playhead)
        workOut = t
        if let a = workIn, a >= t { workIn = nil }
        Haptics.select()
    }

    func clearWork() {
        workIn = nil
        workOut = nil
    }

    func zoomIn() { zoom = min(480, zoom * 1.5) }
    func zoomOut() { zoom = max(4, zoom / 1.5) }
    func fit(width: CGFloat) {
        zoom = min(480, max(4, Double(width - EditorTimeline.pad * 2 - 24) / max(total, 1)))
    }

    // Beats

    func moveBeat(_ id: Int, by offset: Int) {
        guard let i = index(of: id) else { return }
        let j = i + offset
        guard j >= 0, j < state.beats.count else { return }
        mutate { $0.beats.swapAt(i, j) }
        Haptics.select()
    }

    func dropBeat(_ id: Int, at time: Double) {
        guard let from = index(of: id) else { return }
        let s = starts
        var target = 0
        for (i, beat) in state.beats.enumerated() where beat.id != id {
            if s[i] + beat.length / 2 < time { target += 1 }
        }
        guard target != from else { return }
        mutate { state in
            let beat = state.beats.remove(at: from)
            state.beats.insert(beat, at: min(target, state.beats.count))
        }
        Haptics.thud()
        toast?.say("Moved to place \(target + 1).")
    }

    func setBars(_ id: Int, _ bars: Double, tag: String? = nil) {
        guard let i = index(of: id), !state.beats[i].narrated else { return }
        let value = min(8, max(0.5, (bars * 2).rounded() / 2))
        guard value != state.beats[i].bars else { return }
        mutate(tag) { $0.beats[i].bars = value }
        Haptics.select()
    }

    func duplicateBeat(_ id: Int) {
        guard let i = index(of: id) else { return }
        let newID = state.nextID
        mutate { s in
            var copy = s.beats[i]
            copy.id = newID
            s.beats.insert(copy, at: i + 1)
            s.nextID += 1
        }
        selection = .beat(newID)
        Haptics.success()
        toast?.say("Beat \(i + 2) is a copy of beat \(i + 1).")
    }

    func deleteBeat(_ id: Int) {
        guard state.beats.count > 1, let i = index(of: id) else { return }
        mutate { _ = $0.beats.remove(at: i) }
        if selection == .beat(id) { selection = nil }
        if sheet == .beat(id) { sheet = nil }
        playhead = min(playhead, total)
        Haptics.thud()
        toast?.say("Beat \(i + 1) deleted. Undo brings it back.")
    }

    func beatBinding(_ id: Int) -> Binding<EditorBeat> {
        Binding(
            get: { self.state.beats.first { $0.id == id } ?? .placeholder },
            set: { value in
                guard let i = self.index(of: id) else { return }
                self.mutate("beat-\(id)") { $0.beats[i] = value }
            }
        )
    }

    // Clips

    func clipBinding(_ id: Int) -> Binding<EditorClip> {
        Binding(
            get: { self.state.clips.first { $0.id == id } ?? EditorClip(id: -1, kind: .text, start: 0, length: 1) },
            set: { value in
                guard !self.state.trackLocked, let i = self.clipIndex(id) else { return }
                self.mutate("clip-\(id)") { $0.clips[i] = value }
            }
        )
    }

    private func unlocked() -> Bool {
        if state.trackLocked {
            toast?.say(EditorOptions.lockNote)
            return false
        }
        return true
    }

    private func neighbours(of clip: EditorClip) -> (prevEnd: Double, nextStart: Double) {
        let others = state.clips.filter { $0.id != clip.id }
        let prevEnd = others.filter { $0.end <= clip.start + 0.0001 }.map(\.end).max() ?? 0
        let nextStart = others.filter { $0.start >= clip.end - 0.0001 }.map(\.start).min() ?? max(total, clip.end)
        return (prevEnd, nextStart)
    }

    func addClip(_ kind: EditorClipKind) {
        guard !state.trackRemoved, unlocked() else { return }
        let length = 3.0
        var start = frame(playhead)
        for clip in state.clips.sorted(by: { $0.start < $1.start }) where start < clip.end && start + length > clip.start {
            start = clip.end
        }
        guard start + length <= total + 0.001 else {
            toast?.say("No room for a clip there. Move the playhead or delete a clip.")
            return
        }
        let id = state.nextID
        let clip: EditorClip
        if kind == .text {
            clip = EditorClip(id: id, kind: .text, start: start, length: length, top: 40)
        } else {
            clip = EditorClip(id: id, kind: .shape, start: start, length: length, colour: "Accent", left: 35, top: 35, width: 30, height: 18)
        }
        mutate { s in
            s.clips.append(clip)
            s.clips.sort { $0.start < $1.start }
            s.nextID += 1
        }
        selection = .clip(id)
        Haptics.success()
        toast?.say("\(kind.title) clip added at \(EditorFormat.timecode(start)).")
    }

    func moveClip(_ id: Int, by delta: Double) {
        guard unlocked(), let i = clipIndex(id) else { return }
        let clip = state.clips[i]
        let room = neighbours(of: clip)
        let start = frame(min(max(room.prevEnd, clip.start + delta), room.nextStart - clip.length))
        mutate { $0.clips[i].start = start }
    }

    func trimClip(_ id: Int, edge: EditorEdge, by delta: Double) {
        guard unlocked(), let i = clipIndex(id) else { return }
        var clip = state.clips[i]
        let room = neighbours(of: clip)
        let oneFrame = 1.0 / 30
        let end = clip.end
        switch edge {
        case .start:
            let newStart = frame(min(max(room.prevEnd, clip.start + delta), end - oneFrame))
            clip.start = newStart
            clip.length = end - newStart
        case .end:
            let newEnd = frame(max(min(room.nextStart, end + delta), clip.start + oneFrame))
            clip.length = newEnd - clip.start
        }
        clip.fadeIn = min(clip.fadeIn, clip.length)
        clip.fadeOut = min(clip.fadeOut, clip.length)
        mutate { $0.clips[i] = clip }
    }

    func canSplit(_ clip: EditorClip) -> Bool {
        playhead > clip.start + 1.0 / 30 && playhead < clip.end - 1.0 / 30
    }

    func isInside(_ clip: EditorClip) -> Bool { playhead >= clip.start && playhead <= clip.end }

    func splitClip(_ id: Int) {
        guard unlocked(), let i = clipIndex(id), canSplit(state.clips[i]) else { return }
        let cut = frame(playhead)
        let original = state.clips[i]
        let local = cut - original.start
        var left = original
        var right = original
        right.id = state.nextID
        left.length = cut - original.start
        left.fadeOut = 0
        left.fadeIn = min(left.fadeIn, left.length)
        left.keyTimes = original.keyTimes.filter { $0 < local }
        right.start = cut
        right.length = original.end - cut
        right.fadeIn = 0
        right.fadeOut = min(right.fadeOut, right.length)
        right.keyTimes = original.keyTimes.filter { $0 >= local }.map { $0 - local }
        mutate { s in
            s.clips[i] = left
            s.clips.insert(right, at: i + 1)
            s.nextID += 1
        }
        selection = .clip(right.id)
        if sheet == .clip(id) { sheet = .clip(right.id) }
        Haptics.thud()
        toast?.say("Split. The right part is selected.")
    }

    func deleteClip(_ id: Int, closeGap: Bool) {
        guard unlocked(), let i = clipIndex(id) else { return }
        let removed = state.clips[i]
        mutate { s in
            s.clips.remove(at: i)
            if closeGap {
                for j in s.clips.indices where s.clips[j].start >= removed.end - 0.0001 {
                    s.clips[j].start -= removed.length
                }
            }
        }
        if selection == .clip(id) { selection = nil }
        if sheet == .clip(id) { sheet = nil }
        Haptics.thud()
        toast?.say(closeGap ? "Clip deleted. Later clips moved up." : "Clip deleted.")
    }

    func setAnimated(_ id: Int, _ name: String, _ on: Bool) {
        guard unlocked(), let i = clipIndex(id) else { return }
        let clip = state.clips[i]
        let local = frame(playhead - clip.start)
        mutate { s in
            if on {
                s.clips[i].animated.insert(name)
                if local >= 0, local <= clip.length, !s.clips[i].keyTimes.contains(local) {
                    s.clips[i].keyTimes.append(local)
                    s.clips[i].keyTimes.sort()
                }
            } else {
                s.clips[i].animated.remove(name)
                if s.clips[i].animated.isEmpty { s.clips[i].keyTimes = [] }
            }
        }
    }

    func addKeys(_ id: Int) {
        guard unlocked(), let i = clipIndex(id), isInside(state.clips[i]) else { return }
        let local = frame(playhead - state.clips[i].start)
        mutate { s in
            s.clips[i].animated = Set(EditorOptions.keyNames)
            if !s.clips[i].keyTimes.contains(local) {
                s.clips[i].keyTimes.append(local)
                s.clips[i].keyTimes.sort()
            }
        }
        Haptics.success()
        toast?.say("Keyframes added at \(EditorFormat.timecode(playhead)).")
    }

    func motionValue(_ clip: EditorClip, _ name: String) -> String {
        switch name {
        case "Left": return "\(Int(clip.left.rounded()))%"
        case "Top": return "\(Int(clip.top.rounded()))%"
        case "Size": return "100%"
        case "Turn": return "0 degrees"
        default: return "\(Int((clip.opacity * 100).rounded()))%"
        }
    }

    // Track

    func toggleHidden() {
        mutate { $0.trackHidden.toggle() }
        toast?.say(state.trackHidden ? "Overlay track hidden." : "Overlay track shown.")
    }

    func toggleLocked() {
        mutate { $0.trackLocked.toggle() }
        toast?.say(state.trackLocked ? "Overlay track locked." : "Overlay track unlocked.")
    }

    func removeTrack() {
        mutate { s in
            s.trackRemoved = true
            s.clips = []
            s.trackLocked = false
            s.trackHidden = false
        }
        if case .clip(_)? = selection { selection = nil }
        Haptics.thud()
        toast?.say("Overlay track removed. Undo brings it back.")
    }

    func addTrack() {
        mutate { $0.trackRemoved = false }
        toast?.say("Overlay track added.")
    }

    func goToComment(_ comment: EditorComment) {
        seek(comment.time)
        toast?.say("Comment \(comment.id): \(comment.text)")
    }

    // Render

    func startRender(from progress: Double = 0, rate: Double = 0.012) {
        guard !isRendering else { return }
        renderRate = rate
        runRender(from: progress)
    }

    private func runRender(from progress: Double) {
        renderTask?.cancel()
        render = .running(progress)
        renderTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                guard case .running(let current) = self.render else { return }
                let next = current + self.renderRate
                if next >= 1 {
                    self.render = .done
                    Haptics.success()
                    self.toast?.say("Rendered.")
                    return
                }
                self.render = .running(next)
            }
        }
    }

    func stopRender() {
        renderTask?.cancel()
        if case .running(let p) = render { render = .stopped(p) }
    }

    func resumeRender() {
        if case .stopped(let p) = render { runRender(from: p) }
    }

    func closeRender() {
        renderTask?.cancel()
        render = .idle
    }

    // Ask Kairos

    func applyAsk(_ prompt: String) -> Int {
        let i: Int
        if let beat = selectedBeat, let found = index(of: beat.id) { i = found } else { i = currentIndex }
        let lines = [
            "Spring is here. The trails are open.",
            "Rook's old bike needs a little love.",
            "Main street, just before sunset.",
            "A full tune-up while you wait.",
            "Come by this weekend. Prices end Friday.",
        ]
        let words = state.beats[i].caption.split(separator: " ")
        let line: String
        if prompt.lowercased().contains("short"), words.count > 4 {
            line = words.prefix(4).joined(separator: " ") + "."
        } else {
            line = lines[askCount % lines.count]
        }
        askCount += 1
        mutate { $0.beats[i].caption = line }
        selection = .beat(state.beats[i].id)
        return i + 1
    }
}

// MARK: - Formatting and drawing helpers

nonisolated enum EditorFormat {
    static func timecode(_ t: Double) -> String {
        let frames = Int((max(0, t) * 30).rounded())
        return String(format: "%02d:%02d.%02d", frames / 1800, (frames / 30) % 60, frames % 30)
    }

    static func clock(_ t: Double) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func seconds(_ t: Double) -> String { String(format: "%.1f s", t) }

    static func bars(_ b: Double) -> String {
        let count = b == b.rounded() ? String(Int(b)) : String(format: "%.1f", b)
        return "\(count) \(b == 1 ? "bar" : "bars"), \(seconds(b * EditorBeat.secondsPerBar))"
    }

    static func ruler(_ t: Double, step: Double) -> String {
        if step < 1 { return String(format: "%.1f", t) }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

nonisolated enum EditorArt {
    static func sky(_ beat: EditorBeat) -> (top: UInt32, bottom: UInt32, ground: UInt32) {
        let key: String
        switch beat.kind {
        case .scene: key = beat.setting
        case .story: key = beat.timeOfDay == "dusk" ? "dusk" : beat.place
        case .stage: key = beat.world
        case .blocky: key = beat.timeOfDay == "day" ? beat.world : beat.timeOfDay
        }
        switch key {
        case "city": return (0x3E4A6B, 0xC98B6B, 0x4A3B3A)
        case "space", "night": return (0x0F1430, 0x2B2552, 0x3A3560)
        case "room", "party": return (0x6B5442, 0xB89A7A, 0x4E3C30)
        case "ocean", "beach": return (0x5FA8D3, 0xBFE3F0, 0xE3CFA0)
        case "lab": return (0xCFE3E8, 0x8FB4BF, 0x5D7C86)
        case "dusk": return (0x5B3A5E, 0xE39A6B, 0x4A3A3A)
        case "lavender": return (0xB9A8D9, 0xE6DDF2, 0x9C88C4)
        case "peach": return (0xF2B79B, 0xFBE3D3, 0xE09A7A)
        case "mint": return (0x9FD6C0, 0xE2F4EC, 0x6FB79A)
        case "sky", "sky-island", "cliff": return (0x7FB8E6, 0xDDEFFB, 0x5A9AD0)
        case "cave": return (0x2E2A28, 0x5A4E44, 0x3A322C)
        case "village": return (0x9CC7E0, 0xF1E6C8, 0x8AA866)
        default: return (0x8EC5E8, 0xE8F4DA, 0x7DB36A)
        }
    }

    static func label(_ beat: EditorBeat) -> String {
        switch beat.kind {
        case .scene: return "\(beat.setting.capitalized), \(beat.shot) shot"
        case .stage: return "3D \(beat.world) set, \(beat.shot) shot"
        case .blocky: return "Blocky \(beat.world), \(beat.timeOfDay), \(beat.shot) shot"
        case .story: return beat.flashback ? "Flashback: \(beat.caption)" : "Story shot, \(beat.place)"
        }
    }

    static func shotScale(_ shot: String) -> CGFloat {
        switch shot {
        case "wide", "top", "orbit": return 0.15
        case "close": return 0.32
        default: return 0.22
        }
    }

    static func symbol(_ icon: String) -> String {
        switch icon {
        case "sun": return "sun.max.fill"
        case "moon": return "moon.fill"
        case "star": return "star.fill"
        case "cloud": return "cloud.fill"
        case "lightbulb": return "lightbulb.fill"
        case "heart": return "heart.fill"
        case "book": return "book.fill"
        case "planet": return "globe"
        case "drop": return "drop.fill"
        case "leaf", "tree": return "leaf.fill"
        case "gear": return "gearshape.fill"
        case "arrow": return "arrow.right"
        case "question": return "questionmark"
        case "clock": return "clock.fill"
        case "rocket": return "paperplane.fill"
        case "house": return "house.fill"
        case "magnifier": return "magnifyingglass"
        case "atom": return "sparkles"
        default: return "circle.fill"
        }
    }

    static func castColour(_ name: String) -> UInt32 {
        switch name {
        case "Pip": return Palette.botSage
        case "Mara": return Palette.botRose
        case "Pip Block": return Palette.botSand
        default: return Palette.botPowder
        }
    }

    static func clipColour(_ name: String) -> UInt32 {
        switch name {
        case "Soft text": return 0xD9CCB8
        case "Accent": return 0xE2B154
        case "Second accent": return 0x8CB8D9
        case "Background": return 0x1B1612
        case "Surface": return 0x2A221C
        case "White": return 0xFFFFFF
        case "Black": return 0x000000
        default: return 0xF7F1E6
        }
    }

    static func textAlign(_ align: String) -> TextAlignment {
        align == "Left" ? .leading : (align == "Right" ? .trailing : .center)
    }

    static func frameAlign(_ align: String) -> Alignment {
        align == "Left" ? .leading : (align == "Right" ? .trailing : .center)
    }
}

nonisolated enum EditorLane {
    static let ruler: CGFloat = 30
    static let chapters: CGFloat = 22
    static let beats: CGFloat = 48
    static let voice: CGFloat = 30
    static let music: CGFloat = 28
    static let overlay: CGFloat = 38
    static let comments: CGFloat = 30
}

extension View {
    /// Greys out and disables a control in the editor.
    func editorEnabled(_ on: Bool) -> some View {
        disabled(!on).opacity(on ? 1 : 0.4)
    }
}

// MARK: - Preview

struct EditorPreview: View {
    let model: EditorModel

    var body: some View {
        let beat = model.currentBeat
        ZStack {
            EditorSceneArt(beat: beat)
            if beat.kind == .story && beat.flashback {
                Color(hex: 0x704214).opacity(0.35)
            }
            GeometryReader { geo in
                ForEach(model.activeClips) { clip in
                    EditorClipArt(clip: clip)
                        .frame(width: geo.size.width * CGFloat(clip.width) / 100, height: geo.size.height * CGFloat(clip.height) / 100)
                        .opacity(model.clipOpacity(clip))
                        .position(x: geo.size.width * CGFloat(clip.left + clip.width / 2) / 100,
                                  y: geo.size.height * CGFloat(clip.top + clip.height / 2) / 100)
                }
            }
            labels(beat)
            if model.guides {
                GeometryReader { geo in
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .padding(.horizontal, geo.size.width * 0.05)
                        .padding(.vertical, geo.size.height * 0.08)
                }
                .allowsHitTesting(false)
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.togglePlay() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview, beat \(model.currentIndex + 1). \(beat.caption)")
        .accessibilityHint("Plays or pauses")
        .accessibilityAddTraits(.isButton)
    }

    private func labels(_ beat: EditorBeat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("\(model.currentIndex + 1). \(EditorArt.label(beat))")
                    .font(KFont.ui(10.5, .medium, relativeTo: .caption2))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.38), in: Capsule())
                Spacer(minLength: 0)
                if beat.kind == .story && beat.flashback {
                    Text("FLASHBACK")
                        .font(KFont.ui(9.5, .semibold, relativeTo: .caption2))
                        .foregroundStyle(Color(hex: 0xF3E2C0))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: 0x704214), in: Capsule())
                }
            }
            .padding(8)
            Spacer()
            if !beat.caption.isEmpty {
                Text(beat.caption)
                    .font(KFont.ui(12.5, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
            }
        }
    }
}

struct EditorSceneArt: View {
    let beat: EditorBeat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sky = EditorArt.sky(beat)
            ZStack {
                LinearGradient(colors: [Color(hex: sky.top), Color(hex: sky.bottom)], startPoint: .top, endPoint: .bottom)
                Ellipse()
                    .fill(Color(hex: sky.ground))
                    .frame(width: w * 1.7, height: h * 0.42)
                    .position(x: w / 2, y: h * 1.04)
                figures(w: w, h: h)
            }
        }
    }

    @ViewBuilder private func figures(w: CGFloat, h: CGFloat) -> some View {
        let scale = EditorArt.shotScale(beat.kind == .story ? (beat.shots.first ?? "medium") : beat.shot)
        switch beat.kind {
        case .scene:
            ForEach(beat.props) { prop in
                Image(systemName: EditorArt.symbol(prop.icon))
                    .font(.system(size: max(10, w * CGFloat(prop.size) / 100 * 1.4)))
                    .foregroundStyle(Color(hex: 0xFFF3D6))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                    .position(x: w * CGFloat(prop.across) / 100, y: h * 0.28)
            }
            ForEach(beat.characters) { character in
                EditorPuppet(colour: EditorArt.castColour(character.name), speaks: character.speaks, size: w * scale)
                    .position(x: w * CGFloat(character.position) / 100, y: h * 0.7)
            }
        case .story:
            EditorPuppet(colour: EditorArt.castColour(beat.speaker), speaks: true, size: w * scale, square: true)
                .position(x: w * 0.5, y: h * 0.7)
        case .stage:
            if beat.pedestal {
                Ellipse()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: w * 0.5, height: w * 0.12)
                    .position(x: w * 0.5, y: h * 0.7 + w * scale * 0.5)
            }
            EditorPuppet(colour: Palette.botLilac, speaks: true, size: w * scale)
                .position(x: w * 0.5, y: h * 0.7)
        case .blocky:
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(hex: i % 2 == 0 ? 0x7DB36A : 0x6A9E58))
                    .frame(width: w / 7, height: w / 7)
                    .position(x: w / 14 + CGFloat(i) * w / 7, y: h * 0.84)
            }
            EditorPuppet(colour: Palette.botSand, speaks: false, size: w * scale, square: true)
                .position(x: w * 0.4, y: h * 0.68)
        }
    }
}

struct EditorPuppet: View {
    let colour: UInt32
    let speaks: Bool
    let size: CGFloat
    var square = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: square ? size * 0.18 : size / 2, style: .continuous)
                .fill(Color(hex: colour))
            HStack(spacing: size * 0.18) {
                Circle().fill(Color(hex: 0x1B1612)).frame(width: size * 0.1, height: size * 0.1)
                Circle().fill(Color(hex: 0x1B1612)).frame(width: size * 0.1, height: size * 0.1)
            }
            .offset(y: -size * 0.06)
            Capsule()
                .fill(Color(hex: 0x1B1612))
                .frame(width: size * (speaks ? 0.22 : 0.14), height: size * (speaks ? 0.1 : 0.04))
                .offset(y: size * 0.16)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
    }
}

struct EditorClipArt: View {
    let clip: EditorClip

    var body: some View {
        let colour = Color(hex: EditorArt.clipColour(clip.colour))
        switch clip.kind {
        case .text:
            Text(clip.text.isEmpty ? " " : clip.text)
                .font(KFont.ui(clip.size == "Headline" ? 17 : 12, clip.size == "Headline" ? .semibold : .regular))
                .foregroundStyle(colour)
                .multilineTextAlignment(EditorArt.textAlign(clip.align))
                .minimumScaleFactor(0.5)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: EditorArt.frameAlign(clip.align))
                .background {
                    if clip.style == "On a card" {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0x1B1612, alpha: 0.62))
                    }
                }
        case .shape:
            shape(colour)
        }
    }

    @ViewBuilder private func shape(_ colour: Color) -> some View {
        switch clip.shape {
        case "Ellipse":
            if clip.filled { Ellipse().fill(colour) } else { Ellipse().stroke(colour, lineWidth: 3) }
        case "Line":
            Capsule().fill(colour).frame(height: 4)
        case "Arrow":
            Image(systemName: "arrow.right").resizable().scaledToFit().foregroundStyle(colour)
        default:
            if clip.filled {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(colour)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(colour, lineWidth: 3)
            }
        }
    }
}

// MARK: - Timeline

struct EditorTimeline: View {
    let model: EditorModel
    @State private var visibleWidth: CGFloat = 280
    @State private var dragBeat: Int?
    @State private var dragDX: CGFloat = 0
    @State private var trimBase: Double?

    static let pad: CGFloat = 12
    private let headWidth: CGFloat = 66

    private func x(_ t: Double) -> CGFloat { Self.pad + CGFloat(t * model.zoom) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            HStack(alignment: .top, spacing: 0) {
                heads
                ScrollView(.horizontal) { lanes }
                    .scrollIndicators(.hidden)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
            }
            .padding(.vertical, 6)
            .kCard(radius: 18)
        }
    }

    private var toolbar: some View {
        let canAdd = !model.state.trackRemoved && !model.state.trackLocked
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                EditorIconButton(symbol: "minus.magnifyingglass", label: "Zoom out") { model.zoomOut() }
                EditorIconButton(symbol: "plus.magnifyingglass", label: "Zoom in") { model.zoomIn() }
                PillButton(title: "Fit", symbol: "arrow.left.and.right") { model.fit(width: visibleWidth) }
                EditorTogglePill(title: "Snap", isOn: model.snap) { model.snap.toggle() }
                EditorTogglePill(title: "Ripple", isOn: model.ripple) { model.ripple.toggle() }
                PillButton(title: "Text", symbol: "plus") { model.addClip(.text) }
                    .editorEnabled(canAdd)
                    .accessibilityLabel("Add a text clip at the playhead")
                PillButton(title: "Shape", symbol: "plus") { model.addClip(.shape) }
                    .editorEnabled(canAdd)
                    .accessibilityLabel("Add a shape clip at the playhead")
            }
        }
        .scrollIndicators(.hidden)
    }

    private var heads: some View {
        VStack(alignment: .leading, spacing: 0) {
            head("Time", EditorLane.ruler)
            head("Chapters", EditorLane.chapters)
            head("Beats", EditorLane.beats)
            head("Voice", EditorLane.voice)
            head("Music", EditorLane.music)
            if !model.state.trackRemoved {
                head(model.state.trackLocked ? "Overlay, locked" : "Overlay 1", EditorLane.overlay)
            }
            head("Comments", EditorLane.comments)
        }
        .frame(width: headWidth)
        .overlay(alignment: .trailing) { Palette.line.frame(width: 1) }
    }

    private func head(_ text: String, _ height: CGFloat) -> some View {
        Text(text)
            .font(KFont.ui(11.5, .medium, relativeTo: .caption2))
            .foregroundStyle(Palette.inkFaint)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(width: headWidth - 10, height: height, alignment: .leading)
            .padding(.leading, 10)
    }

    private var lanes: some View {
        let width = x(model.total) + 48
        return VStack(alignment: .leading, spacing: 0) {
            ruler(width)
            chapterLane(width)
            beatLane(width)
            voiceLane(width)
            musicLane(width)
            if !model.state.trackRemoved { overlayLane(width) }
            commentLane(width)
        }
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(Palette.gold)
                .frame(width: 2)
                .offset(x: x(model.playhead) - 1)
                .allowsHitTesting(false)
        }
        .animation(Motion.snappy, value: model.state)
        .animation(Motion.snappy, value: model.zoom)
    }

    private func ruler(_ width: CGFloat) -> some View {
        let step = model.rulerStep
        let count = Int(model.total / step)
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(0...count), id: \.self) { i in
                VStack(alignment: .leading, spacing: 1) {
                    Rectangle().fill(Palette.lineStrong).frame(width: 1, height: 7)
                    Text(EditorFormat.ruler(Double(i) * step, step: step))
                        .font(KFont.ui(10.5, relativeTo: .caption2))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize()
                }
                .offset(x: x(Double(i) * step))
            }
            Circle()
                .fill(Palette.gold)
                .frame(width: 12, height: 12)
                .offset(x: x(model.playhead) - 6, y: EditorLane.ruler - 13)
        }
        .frame(width: width, height: EditorLane.ruler, alignment: .topLeading)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in model.scrub(to: Double(value.location.x - Self.pad) / model.zoom) }
        )
        .accessibilityElement()
        .accessibilityLabel("Playhead")
        .accessibilityValue(EditorFormat.timecode(model.playhead))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.step(frames: 15)
            case .decrement: model.step(frames: -15)
            @unknown default: break
            }
        }
    }

    private func chapterLane(_ width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.chapterMarks) { mark in
                HStack(spacing: 3) {
                    Image(systemName: "flag.fill").font(.system(size: 9, weight: .semibold))
                    Text("\(mark.number). \(mark.title)")
                        .font(KFont.ui(11, .medium, relativeTo: .caption2))
                        .fixedSize()
                }
                .foregroundStyle(Palette.goldText)
                .offset(x: x(mark.time) + 2, y: 4)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(width: width, height: EditorLane.chapters, alignment: .topLeading)
    }

    private func beatLane(_ width: CGFloat) -> some View {
        let starts = model.starts
        let beats = model.state.beats
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(beats.enumerated()), id: \.element.id) { index, beat in
                if index < starts.count {
                    beatClip(beat, index: index, start: starts[index])
                }
            }
        }
        .frame(width: width, height: EditorLane.beats, alignment: .topLeading)
    }

    private func beatClip(_ beat: EditorBeat, index: Int, start: Double) -> some View {
        let w = max(CGFloat(beat.length * model.zoom) - 3, 8)
        let selected = model.selection == .beat(beat.id)
        let dragging = dragBeat == beat.id
        return EditorBeatChip(beat: beat, number: index + 1, selected: selected)
            .overlay(alignment: .trailing) {
                if !beat.narrated { trimHandle(beat, selected: selected) }
            }
            .frame(width: w, height: EditorLane.beats - 8)
            .scaleEffect(dragging ? 1.04 : 1)
            .shadow(color: .black.opacity(dragging ? 0.25 : 0), radius: 8, y: 4)
            .offset(x: x(start) + 1 + (dragging ? dragDX : 0), y: 4)
            .zIndex(dragging ? 1 : 0)
            .onTapGesture {
                Haptics.select()
                model.select(.beat(beat.id))
            }
            .gesture(reorderGesture(beat, centre: start + beat.length / 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Beat \(index + 1), \(beat.kind.title), \(EditorFormat.seconds(beat.length))")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.select(.beat(beat.id)) }
    }

    private func reorderGesture(_ beat: EditorBeat, centre: Double) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if dragBeat != beat.id {
                        dragBeat = beat.id
                        model.select(.beat(beat.id))
                        Haptics.thud()
                    }
                    dragDX = drag?.translation.width ?? 0
                default:
                    break
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value {
                    model.dropBeat(beat.id, at: centre + Double(drag.translation.width) / model.zoom)
                }
                dragBeat = nil
                dragDX = 0
            }
    }

    private func trimHandle(_ beat: EditorBeat, selected: Bool) -> some View {
        Capsule()
            .fill(selected ? Palette.gold : Palette.inkFaint)
            .frame(width: 4, height: 20)
            .frame(width: 20, height: EditorLane.beats - 8)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = trimBase ?? beat.bars
                        if trimBase == nil {
                            trimBase = beat.bars
                            model.select(.beat(beat.id))
                        }
                        let bars = base + Double(value.translation.width) / model.zoom / EditorBeat.secondsPerBar
                        model.setBars(beat.id, bars, tag: "trim-\(beat.id)")
                    }
                    .onEnded { _ in trimBase = nil }
            )
            .accessibilityLabel("Drag to change its length in bars")
    }

    private func voiceLane(_ width: CGFloat) -> some View {
        let zoom = model.zoom
        let pad = Self.pad
        let spans = model.narrationSpans
        let colour = Palette.goldText.opacity(0.8)
        return Canvas { context, size in
            for span in spans {
                let x0 = pad + CGFloat(span.start * zoom)
                let x1 = pad + CGFloat(span.end * zoom)
                var xPos = x0 + 2
                var i = 0
                while xPos < x1 - 2 {
                    let wave = abs(sin(Double(i) * 0.7 + Double(span.seed))) * (0.55 + 0.45 * abs(sin(Double(i) * 0.17 + 1)))
                    let barHeight = max(2, (size.height - 8) * CGFloat(wave))
                    let rect = CGRect(x: xPos, y: (size.height - barHeight) / 2, width: 2, height: barHeight)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colour))
                    xPos += 4
                    i += 1
                }
            }
        }
        .frame(width: width, height: EditorLane.voice)
        .accessibilityLabel("Narration waveform")
    }

    private func musicLane(_ width: CGFloat) -> some View {
        let zoom = model.zoom
        let pad = Self.pad
        let total = model.total
        let spans = model.narrationSpans
        let line = Palette.success
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.success.opacity(0.14))
                .frame(width: CGFloat(total * zoom), height: EditorLane.music - 6)
                .offset(x: pad, y: 3)
            Canvas { context, size in
                var path = Path()
                let high = size.height * 0.32
                let low = size.height * 0.7
                let endX = pad + CGFloat(total * zoom)
                var xPos = pad
                while xPos <= endX {
                    let t = Double(xPos - pad) / zoom
                    var duck = 0.0
                    for span in spans {
                        let d: Double
                        if t >= span.start && t <= span.end {
                            d = 1
                        } else if t < span.start {
                            d = max(0, 1 - (span.start - t) / 0.4)
                        } else {
                            d = max(0, 1 - (t - span.end) / 0.4)
                        }
                        duck = max(duck, d)
                    }
                    let point = CGPoint(x: xPos, y: high + (low - high) * CGFloat(duck))
                    if xPos == pad { path.move(to: point) } else { path.addLine(to: point) }
                    xPos += 3
                }
                context.stroke(path, with: .color(line), lineWidth: 1.5)
            }
            Text("Music, Warm")
                .font(KFont.ui(11, .medium, relativeTo: .caption2))
                .foregroundStyle(Palette.ink)
                .fixedSize()
                .offset(x: pad + 8, y: 6)
        }
        .frame(width: width, height: EditorLane.music, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Music, Warm. It dips under the voice.")
    }

    private func overlayLane(_ width: CGFloat) -> some View {
        let s = model.state
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(s.clips) { clip in
                EditorClipChip(clip: clip, selected: model.selection == .clip(clip.id), locked: s.trackLocked)
                    .frame(width: max(CGFloat(clip.length * model.zoom) - 2, 8), height: EditorLane.overlay - 8)
                    .offset(x: x(clip.start) + 1, y: 4)
                    .onTapGesture {
                        Haptics.select()
                        model.select(.clip(clip.id))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(clip.kind.title) clip, \(clip.label)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.select(.clip(clip.id)) }
            }
        }
        .frame(width: width, height: EditorLane.overlay, alignment: .topLeading)
        .opacity(s.trackHidden ? 0.45 : 1)
    }

    private func commentLane(_ width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.comments) { comment in
                Button {
                    Haptics.tap()
                    model.goToComment(comment)
                } label: {
                    Text("\(comment.id)")
                        .font(KFont.ui(11, .semibold, relativeTo: .caption2))
                        .foregroundStyle(Palette.onGold)
                        .frame(width: 20, height: 20)
                        .background(Palette.gold, in: Circle())
                        .frame(width: 44, height: EditorLane.comments)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .offset(x: x(comment.time) - 22)
                .accessibilityLabel("Comment \(comment.id): \(comment.text)")
            }
        }
        .frame(width: width, height: EditorLane.comments, alignment: .topLeading)
    }
}

struct EditorBeatChip: View {
    let beat: EditorBeat
    let number: Int
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        shape
            .fill(selected ? Palette.gold.opacity(0.3) : Palette.surface2)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(number) \(beat.kind.title)")
                        .font(KFont.ui(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(Palette.ink)
                    Text(beat.narrated ? EditorFormat.seconds(beat.length) : EditorFormat.bars(beat.bars))
                        .font(KFont.ui(10.5, relativeTo: .caption2))
                        .foregroundStyle(Palette.inkFaint)
                }
                .lineLimit(1)
                .padding(.leading, 7)
                .padding(.top, 5)
                .padding(.trailing, beat.narrated ? 4 : 18)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(selected ? Palette.gold : Palette.line, lineWidth: selected ? 1.5 : 1))
    }
}

struct EditorClipChip: View {
    let clip: EditorClip
    let selected: Bool
    let locked: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        shape
            .fill(Palette.working.opacity(selected ? 0.42 : 0.22))
            .overlay(alignment: .leading) {
                HStack(spacing: 4) {
                    Image(systemName: locked ? "lock.fill" : (clip.kind == .text ? "textformat" : "square.on.circle"))
                        .font(.system(size: 9, weight: .bold))
                    Text(clip.label)
                        .font(KFont.ui(11, .medium, relativeTo: .caption2))
                        .lineLimit(1)
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 6)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(selected ? Palette.gold : Palette.working.opacity(0.5), lineWidth: selected ? 1.5 : 1))
    }
}

// MARK: - Track row and selection panel

struct EditorTrackRow: View {
    let model: EditorModel

    var body: some View {
        let s = model.state
        VStack(alignment: .leading, spacing: 10) {
            if s.trackRemoved {
                HStack(spacing: 10) {
                    Text("No overlay track.")
                        .font(KFont.ui(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                    Spacer(minLength: 4)
                    PillButton(title: "Add overlay track", symbol: "plus") { model.addTrack() }
                }
            } else {
                HStack(spacing: 6) {
                    Text("Overlay 1")
                        .font(KFont.ui(15.5, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                    Text("\(s.clips.count) \(s.clips.count == 1 ? "clip" : "clips")")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                    Spacer(minLength: 4)
                    if s.trackHidden { StatePill(text: "Hidden", tone: .muted) }
                    if s.trackLocked { StatePill(text: "Locked", tone: .warn) }
                }
                HStack(spacing: 8) {
                    PillButton(title: s.trackHidden ? "Show" : "Hide", symbol: s.trackHidden ? "eye" : "eye.slash", expand: true) {
                        model.toggleHidden()
                    }
                    PillButton(title: s.trackLocked ? "Unlock" : "Lock", symbol: s.trackLocked ? "lock.open.fill" : "lock.fill", expand: true) {
                        model.toggleLocked()
                    }
                    PillButton(title: "Remove", symbol: "trash", danger: true, expand: true) { model.removeTrack() }
                }
                if s.trackLocked {
                    Text(EditorOptions.lockNote)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.goldText)
                }
            }
        }
        .padding(12)
        .kCard(radius: 18)
    }
}

struct EditorSelectionPanel: View {
    let model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let beat = model.selectedBeat, let index = model.index(of: beat.id) {
                beatPanel(beat, index: index)
            } else if let clip = model.selectedClip {
                clipPanel(clip)
            } else {
                EmptyLine(text: "Tap a beat or a clip on the timeline to change it. Hold a beat and drag to move it.")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 20)
        .animation(Motion.snappy, value: model.selection)
    }

    @ViewBuilder private func beatPanel(_ beat: EditorBeat, index: Int) -> some View {
        let count = model.state.beats.count
        VStack(alignment: .leading, spacing: 2) {
            Text("Beat \(index + 1), \(beat.kind.title)")
                .font(KFont.ui(17, .semibold, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
            Text(EditorArt.label(beat))
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(2)
        }
        HStack(spacing: 8) {
            PillButton(title: "Move earlier", symbol: "chevron.left", expand: true) { model.moveBeat(beat.id, by: -1) }
                .editorEnabled(index > 0)
            PillButton(title: "Move later", symbol: "chevron.right", expand: true) { model.moveBeat(beat.id, by: 1) }
                .editorEnabled(index < count - 1)
        }
        if beat.narrated {
            Text("Length set by its narration. \(EditorFormat.seconds(beat.length)).")
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
        } else {
            EditorStepRow(title: "Length", value: EditorFormat.bars(beat.bars),
                          canMinus: beat.bars > 0.5, canPlus: beat.bars < 8, last: true,
                          minus: { model.setBars(beat.id, beat.bars - 0.5) },
                          plus: { model.setBars(beat.id, beat.bars + 0.5) })
                .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        HStack(spacing: 8) {
            PillButton(title: "Edit beat", symbol: "slider.horizontal.3", filled: true, expand: true) { model.sheet = .beat(beat.id) }
            PillButton(title: "Duplicate", symbol: "plus.square.on.square", expand: true) { model.duplicateBeat(beat.id) }
            EditorIconButton(symbol: "trash", label: "Delete beat", enabled: count > 1) { model.deleteBeat(beat.id) }
        }
    }

    @ViewBuilder private func clipPanel(_ clip: EditorClip) -> some View {
        let locked = model.state.trackLocked
        VStack(alignment: .leading, spacing: 2) {
            Text("\(clip.kind.title) clip \(clip.id)")
                .font(KFont.ui(17, .semibold, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
            Text("\(clip.label). \(EditorFormat.timecode(clip.start)) to \(EditorFormat.timecode(clip.end)), \(EditorFormat.seconds(clip.length))")
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(2)
        }
        if locked {
            Text(EditorOptions.lockNote)
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.goldText)
        }
        Group {
            VStack(spacing: 0) {
                EditorStepRow(title: "Left edge", value: EditorFormat.timecode(clip.start),
                              minus: { model.trimClip(clip.id, edge: .start, by: -0.25) },
                              plus: { model.trimClip(clip.id, edge: .start, by: 0.25) })
                EditorStepRow(title: "Right edge", value: EditorFormat.timecode(clip.end), last: true,
                              minus: { model.trimClip(clip.id, edge: .end, by: -0.25) },
                              plus: { model.trimClip(clip.id, edge: .end, by: 0.25) })
            }
            .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            PillButton(title: "Split at playhead", symbol: "scissors", expand: true) { model.splitClip(clip.id) }
                .editorEnabled(model.canSplit(clip) && !locked)
            HStack(spacing: 8) {
                PillButton(title: "Delete", symbol: "trash", danger: true, expand: true) {
                    model.deleteClip(clip.id, closeGap: model.ripple)
                }
                PillButton(title: "Close the gap", symbol: "arrow.left.to.line", danger: true, expand: true) {
                    model.deleteClip(clip.id, closeGap: true)
                }
                .accessibilityLabel("Delete and close the gap")
            }
        }
        .disabled(locked)
        PillButton(title: "Edit clip", symbol: "slider.horizontal.3", filled: true, expand: true) { model.sheet = .clip(clip.id) }
    }
}

// MARK: - Render

struct EditorRenderCard: View {
    let model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Render")
                    .font(KFont.ui(16, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Spacer()
                pill
            }
            content
        }
        .padding(14)
        .kCard(radius: 20)
    }

    static func stage(_ p: Double) -> String {
        if p < 0.25 { return "Narration" }
        if p < 0.6 { return "Frames" }
        if p < 0.8 { return "Music" }
        return "Encoding"
    }

    @ViewBuilder private var pill: some View {
        switch model.render {
        case .running: StatePill(text: "Rendering", tone: .working)
        case .stopped: StatePill(text: "Stopped", tone: .warn)
        case .done: StatePill(text: "Ready", tone: .ok)
        case .idle: EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch model.render {
        case .running(let p):
            progress(p)
            HStack(spacing: 10) {
                Text("\(Self.stage(p)), \(Int(p * 100))%")
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .contentTransition(.numericText())
                Spacer()
                PillButton(title: "Stop", symbol: "stop.fill") { model.stopRender() }
            }
        case .stopped(let p):
            progress(p)
            HStack(spacing: 8) {
                Text("Stopped at \(Int(p * 100))%")
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                Spacer(minLength: 4)
                PillButton(title: "Cancel") { model.closeRender() }
                PillButton(title: "Resume", symbol: "play.fill", filled: true) { model.resumeRender() }
            }
        case .done:
            Text("Rendered. \(EditorFormat.clock(model.total)), 1080 x 1920.")
                .font(KFont.ui(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 44, height: 44)
                    .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("spring-ride.mp4")
                        .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                    Text("\(EditorFormat.clock(model.total)), 1080 x 1920, 30 fps")
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                PillButton(title: "Watch", symbol: "play.fill", expand: true) {
                    model.seek(0)
                    model.play()
                }
                PillButton(title: "Close", expand: true) { model.closeRender() }
            }
        case .idle:
            EmptyView()
        }
    }

    private func progress(_ p: Double) -> some View {
        Capsule()
            .fill(Palette.ink.opacity(0.1))
            .frame(height: 8)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(Palette.gold).frame(width: geo.size.width * CGFloat(p))
                }
            }
            .animation(Motion.gentle, value: p)
            .accessibilityElement()
            .accessibilityLabel("Render progress")
            .accessibilityValue("\(Int(p * 100))%")
    }
}

// MARK: - Sheets

struct EditorSheetHost: View {
    let model: EditorModel
    let sheet: EditorSheet

    var body: some View {
        switch sheet {
        case .beat(let id): EditorBeatSheet(model: model, beatID: id)
        case .clip(let id): EditorClipSheet(model: model, clipID: id)
        case .ask: EditorAskSheet(model: model)
        }
    }
}

struct EditorBeatSheet: View {
    let model: EditorModel
    let beatID: Int

    var body: some View {
        ScrollView {
            if let index = model.index(of: beatID) {
                EditorBeatForm(model: model, beat: model.beatBinding(beatID), number: index + 1)
            } else {
                EmptyLine(text: "This beat was removed.")
                    .padding(.top, 40)
                    .padding(.horizontal, 20)
            }
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
    }
}

struct EditorBeatForm: View {
    let model: EditorModel
    @Binding var beat: EditorBeat
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetTitle(title: "\(beat.kind.title) beat \(number)", detail: "\(EditorArt.label(beat)). \(EditorFormat.seconds(beat.length)).")
            MakeField(label: "Caption", text: $beat.caption, prompt: "What this beat says", limit: 140, lines: 1...3)
            lengthGroup
            switch beat.kind {
            case .scene: sceneFields
            case .story: storyFields
            case .stage: stageFields
            case .blocky: blockyFields
            }
            HStack(spacing: 8) {
                PillButton(title: "Duplicate beat", symbol: "plus.square.on.square", expand: true) { model.duplicateBeat(beat.id) }
                PillButton(title: "Delete beat", symbol: "trash", danger: true, expand: true) { model.deleteBeat(beat.id) }
                    .editorEnabled(model.state.beats.count > 1)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 28)
    }

    private var lengthGroup: some View {
        EditorGroup {
            if beat.narrated {
                Text("Length set by its narration.")
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EditorStepRow(title: "Length", value: EditorFormat.bars(beat.bars),
                              canMinus: beat.bars > 0.5, canPlus: beat.bars < 8, last: true,
                              minus: { beat.bars = max(0.5, beat.bars - 0.5) },
                              plus: { beat.bars = min(8, beat.bars + 0.5) })
            }
        }
    }

    // Scene beat

    @ViewBuilder private var sceneFields: some View {
        EditorGroup {
            MakeChoiceRow(title: "Setting", options: EditorOptions.settings, selection: $beat.setting)
            MakeChoiceRow(title: "Shot", options: EditorOptions.shots, selection: $beat.shot, last: true)
        }
        SectionLabel(text: "Characters on screen (\(beat.characters.count) of 3)")
        ForEach(beat.characters) { character in
            characterCard(character.id)
        }
        PillButton(title: "Add a character", symbol: "plus") { addCharacter() }
            .editorEnabled(beat.characters.count < 3)
        SectionLabel(text: "Props (\(beat.props.count) of 6)")
        ForEach(beat.props) { prop in
            propCard(prop.id)
        }
        PillButton(title: "Add a prop", symbol: "plus") { addProp() }
            .editorEnabled(beat.props.count < 6)
    }

    private func characterBinding(_ id: Int) -> Binding<EditorCharacter> {
        Binding(
            get: { beat.characters.first { $0.id == id } ?? EditorCharacter(id: id, name: "Pip", position: 50) },
            set: { value in
                guard let i = beat.characters.firstIndex(where: { $0.id == id }) else { return }
                var list = beat.characters
                if value.speaks && !list[i].speaks {
                    for j in list.indices { list[j].speaks = false }
                }
                list[i] = value
                beat.characters = list
            }
        )
    }

    private func characterCard(_ id: Int) -> some View {
        let c = characterBinding(id)
        return EditorGroup {
            MakeChoiceRow(title: "Character", options: EditorOptions.cast, selection: c.name)
            EditorSliderRow(title: "Position", value: c.position, range: 0...100, text: "\(Int(c.wrappedValue.position))% across")
            MakeChoiceRow(title: "Expression", options: EditorOptions.expressions, selection: c.expression)
            MakeChoiceRow(title: "Action", options: EditorOptions.actions, selection: c.action)
            MakeToggleRow(title: "Speaks the narration", detail: "One at a time. The mouth follows the voice.", isOn: c.speaks)
            EditorRemoveRow { beat.characters.removeAll { $0.id == id } }
        }
    }

    private func addCharacter() {
        guard beat.characters.count < 3 else { return }
        let next = (beat.characters.map(\.id).max() ?? 0) + 1
        let name = EditorOptions.cast[beat.characters.count % EditorOptions.cast.count]
        beat.characters.append(EditorCharacter(id: next, name: name, position: Double(20 + 30 * beat.characters.count)))
    }

    private func propBinding(_ id: Int) -> Binding<EditorProp> {
        Binding(
            get: { beat.props.first { $0.id == id } ?? EditorProp(id: id, icon: "star", across: 50, size: 10) },
            set: { value in
                guard let i = beat.props.firstIndex(where: { $0.id == id }) else { return }
                beat.props[i] = value
            }
        )
    }

    private func propCard(_ id: Int) -> some View {
        let p = propBinding(id)
        return EditorGroup {
            MakeChoiceRow(title: "Icon", options: EditorOptions.icons, selection: p.icon)
            EditorSliderRow(title: "Across", value: p.across, range: 0...100, text: "\(Int(p.wrappedValue.across))%")
            EditorSliderRow(title: "Size", value: p.size, range: 4...40, text: "\(Int(p.wrappedValue.size))% of the frame")
            MakeToggleRow(title: "Floats gently", isOn: p.floats)
            EditorRemoveRow { beat.props.removeAll { $0.id == id } }
        }
    }

    private func addProp() {
        guard beat.props.count < 6 else { return }
        let next = (beat.props.map(\.id).max() ?? 0) + 1
        let icon = EditorOptions.icons[(beat.props.count * 3) % EditorOptions.icons.count]
        beat.props.append(EditorProp(id: next, icon: icon, across: Double(15 + 14 * beat.props.count), size: 10))
    }

    // Story beat

    private var keyWordCount: Int {
        beat.keyWords.split(separator: ",").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    @ViewBuilder private var storyFields: some View {
        EditorGroup {
            MakeChoiceRow(title: "Who speaks it", options: EditorOptions.speakers, selection: $beat.speaker)
            EditorSliderRow(title: "Gap after the line", value: $beat.gap, range: 0.1...1.6, step: 0.1,
                            text: String(format: "%.1f s", beat.gap))
            MakeToggleRow(title: "Flashback", detail: "Sepia, with a FLASHBACK tag", isOn: $beat.flashback, last: true)
        }
        VStack(alignment: .leading, spacing: 6) {
            MakeField(label: "Key words", text: $beat.keyWords, prompt: "bike, spring, tune-up")
            Text("\(keyWordCount) of 8. Comma separated. The captions show them in the speaker's colour.")
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
        }
        .onChange(of: beat.keyWords) {
            let parts = beat.keyWords.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count > 8 { beat.keyWords = parts.prefix(8).joined(separator: ",") }
        }
        EditorGroup {
            MakeChoiceRow(title: "Place", options: EditorOptions.places, selection: $beat.place)
            MakeChoiceRow(title: "Time of day", options: EditorOptions.storyTimes, selection: $beat.timeOfDay, last: true)
        }
        SectionLabel(text: "Shots (\(beat.shots.count) of 3)")
        EditorGroup {
            ForEach(Array(beat.shots.indices), id: \.self) { i in
                HStack(spacing: 0) {
                    MakeChoiceRow(title: "Shot \(i + 1)", options: EditorOptions.storyShots, selection: shotBinding(i),
                                  last: i == beat.shots.count - 1)
                    if i > 0 {
                        EditorIconButton(symbol: "minus", label: "Remove shot \(i + 1)") {
                            if i < beat.shots.count { beat.shots.remove(at: i) }
                        }
                        .padding(.trailing, 8)
                    }
                }
            }
        }
        PillButton(title: "Add a shot", symbol: "plus") { beat.shots.append("medium") }
            .editorEnabled(beat.shots.count < 3)
    }

    private func shotBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < beat.shots.count ? beat.shots[i] : "medium" },
            set: { value in
                if i < beat.shots.count { beat.shots[i] = value }
            }
        )
    }

    // 3D stage and blocky world beats

    private var stageFields: some View {
        EditorGroup {
            MakeChoiceRow(title: "Set", options: EditorOptions.stageSets, selection: $beat.world)
            MakeChoiceRow(title: "Shot", options: EditorOptions.shots, selection: $beat.shot)
            MakeToggleRow(title: "A pedestal under the cast", isOn: $beat.pedestal, last: true)
        }
    }

    private var blockyFields: some View {
        EditorGroup {
            MakeChoiceRow(title: "World", options: EditorOptions.worlds, selection: $beat.world)
            MakeChoiceRow(title: "Time of day", options: EditorOptions.worldTimes, selection: $beat.timeOfDay)
            MakeChoiceRow(title: "Shot", options: EditorOptions.shots, selection: $beat.shot, last: true)
        }
    }
}

struct EditorClipSheet: View {
    let model: EditorModel
    let clipID: Int

    var body: some View {
        ScrollView {
            if model.clipIndex(clipID) != nil {
                EditorClipForm(model: model, clip: model.clipBinding(clipID))
            } else {
                EmptyLine(text: "This clip was removed.")
                    .padding(.top, 40)
                    .padding(.horizontal, 20)
            }
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
    }
}

struct EditorClipForm: View {
    let model: EditorModel
    @Binding var clip: EditorClip

    var body: some View {
        let locked = model.state.trackLocked
        VStack(alignment: .leading, spacing: 16) {
            SheetTitle(title: "\(clip.kind.title) clip \(clip.id)",
                       detail: "Overlay 1, \(EditorFormat.timecode(clip.start)) to \(EditorFormat.timecode(clip.end)), \(EditorFormat.seconds(clip.length))")
            if locked {
                Text(EditorOptions.lockNote)
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.goldText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kCard(radius: 16)
            }
            Group {
                if clip.kind == .text { textFields } else { shapeFields }
                timing
                look
                motion
                SectionLabel(text: "Track")
                Text("Overlay 1. Later tracks draw on top, and captions stay above every track.")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kCard(radius: 18)
                actions
            }
            .disabled(locked)
            .opacity(locked ? 0.5 : 1)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 28)
    }

    @ViewBuilder private var textFields: some View {
        MakeField(label: "Clip text", text: $clip.text, prompt: "Your text", limit: 140, lines: 2...4)
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Size")
            GlassSwitch(items: ["Headline", "Body"], selection: $clip.size) { $0 }
            SectionLabel(text: "Style")
            GlassSwitch(items: ["On a card", "Plain"], selection: $clip.style) { $0 }
            SectionLabel(text: "Align")
            GlassSwitch(items: ["Left", "Center", "Right"], selection: $clip.align) { $0 }
        }
        EditorGroup {
            MakeChoiceRow(title: "Colour", options: EditorOptions.colours, selection: $clip.colour, last: true)
        }
    }

    private var shapeFields: some View {
        EditorGroup {
            MakeChoiceRow(title: "Shape", options: EditorOptions.shapes, selection: $clip.shape)
            MakeChoiceRow(title: "Colour", options: EditorOptions.colours, selection: $clip.colour)
            MakeToggleRow(title: "Filled", detail: "Off draws the outline", isOn: $clip.filled, last: true)
        }
    }

    @ViewBuilder private var timing: some View {
        SectionLabel(text: "Timing")
        EditorGroup {
            EditorStepRow(title: "Start", value: EditorFormat.timecode(clip.start),
                          minus: { model.moveClip(clip.id, by: -0.1) },
                          plus: { model.moveClip(clip.id, by: 0.1) })
            EditorStepRow(title: "Length", value: EditorFormat.seconds(clip.length),
                          minus: { model.trimClip(clip.id, edge: .end, by: -0.1) },
                          plus: { model.trimClip(clip.id, edge: .end, by: 0.1) })
            EditorStepRow(title: "Fade in", value: EditorFormat.seconds(clip.fadeIn),
                          canMinus: clip.fadeIn > 0.001, canPlus: clip.fadeIn < min(10, clip.length) - 0.001,
                          minus: { clip.fadeIn = max(0, (clip.fadeIn * 10 - 1).rounded() / 10) },
                          plus: { clip.fadeIn = min(min(10, clip.length), (clip.fadeIn * 10 + 1).rounded() / 10) })
            EditorStepRow(title: "Fade out", value: EditorFormat.seconds(clip.fadeOut),
                          canMinus: clip.fadeOut > 0.001, canPlus: clip.fadeOut < min(10, clip.length) - 0.001, last: true,
                          minus: { clip.fadeOut = max(0, (clip.fadeOut * 10 - 1).rounded() / 10) },
                          plus: { clip.fadeOut = min(min(10, clip.length), (clip.fadeOut * 10 + 1).rounded() / 10) })
        }
    }

    @ViewBuilder private var look: some View {
        EditorGroup {
            if clip.animated.contains("Opacity") {
                Text("Opacity is animated: change it under Motion.")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EditorSliderRow(title: "Opacity", value: $clip.opacity, range: 0...1, step: 0.01,
                                text: "\(Int((clip.opacity * 100).rounded()))%", last: true)
            }
        }
        SectionLabel(text: "Position and size")
        EditorGroup {
            EditorSliderRow(title: "Left", value: $clip.left, range: 0...100, text: "\(Int(clip.left))%")
            EditorSliderRow(title: "Top", value: $clip.top, range: 0...100, text: "\(Int(clip.top))%")
            EditorSliderRow(title: "Width", value: $clip.width, range: 1...100, text: "\(Int(clip.width))%")
            EditorSliderRow(title: "Height", value: $clip.height, range: 1...100, text: "\(Int(clip.height))%", last: true)
        }
        Text("Shares of the frame. Text stays readable inside 5% to 95%.")
            .font(KFont.ui(13, relativeTo: .footnote))
            .foregroundStyle(Palette.inkFaint)
    }

    private func animateBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { clip.animated.contains(name) },
            set: { on in model.setAnimated(clip.id, name, on) }
        )
    }

    @ViewBuilder private var motion: some View {
        let inside = model.isInside(clip)
        SectionLabel(text: "Motion")
        EditorGroup {
            ForEach(EditorOptions.keyNames, id: \.self) { name in
                MakeToggleRow(title: "Animate \(name.lowercased())",
                              detail: "\(model.motionValue(clip, name)) at the playhead",
                              isOn: animateBinding(name), last: name == "Opacity")
            }
        }
        PillButton(title: "Add keyframes here", symbol: "diamond.fill") { model.addKeys(clip.id) }
            .editorEnabled(inside)
        if !inside {
            Text("Move the playhead inside the clip to add keyframes.")
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
        }
        if !clip.keyTimes.isEmpty {
            SectionLabel(text: "Keyframes of this clip")
            VStack(spacing: 0) {
                ForEach(clip.keyTimes, id: \.self) { key in
                    Button {
                        Haptics.select()
                        model.seek(clip.start + key)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.goldText)
                            Text("Go to the keyframe at \(EditorFormat.timecode(clip.start + key))")
                                .font(KFont.ui(15, relativeTo: .subheadline))
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                }
            }
            .kCard(radius: 18)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            PillButton(title: "Split at playhead", symbol: "scissors", expand: true) { model.splitClip(clip.id) }
                .editorEnabled(model.canSplit(clip))
            PillButton(title: "Delete clip", symbol: "trash", danger: true, expand: true) {
                model.deleteClip(clip.id, closeGap: model.ripple)
            }
            PillButton(title: "Delete and close the gap", symbol: "arrow.left.to.line", danger: true, expand: true) {
                model.deleteClip(clip.id, closeGap: true)
            }
        }
        .padding(.top, 4)
    }
}

struct EditorAskSheet: View {
    let model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false

    private let ideas = ["Make the opening shorter", "Warmer caption for this beat", "Punchier last line", "Say the sale ends Friday"]

    var body: some View {
        FittedSheet(estimate: 440) {
            VStack(alignment: .leading, spacing: 16) {
                SheetTitle(title: "Ask Kairos", detail: "Kairos changes the video for you. Undo takes any change back.")
                MakeField(label: "What should change?", text: $text, prompt: "Make the opening shorter", lines: 2...4)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(ideas, id: \.self) { idea in
                            Button {
                                Haptics.select()
                                text = idea
                            } label: {
                                Chip(text: idea, filled: text == idea)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
                .scrollIndicators(.hidden)
                if working {
                    HStack(spacing: 10) {
                        PulsingDot(color: Palette.working)
                        Text("Kairos is working on beat \(targetNumber).")
                            .font(KFont.ui(14.5, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkDim)
                    }
                    .transition(.opacity)
                }
                GoldButton(title: working ? "Working" : "Send") { send() }
                    .editorEnabled(!working && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .animation(Motion.snappy, value: working)
        }
    }

    private var targetNumber: Int {
        if let beat = model.selectedBeat, let i = model.index(of: beat.id) { return i + 1 }
        return model.currentIndex + 1
    }

    private func send() {
        Haptics.tap()
        working = true
        let prompt = text
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            let number = model.applyAsk(prompt)
            Haptics.success()
            model.toast?.say("Kairos changed beat \(number).")
            working = false
            dismiss()
        }
    }
}

// MARK: - Small pieces

struct EditorGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .kCard(radius: 20)
    }
}

struct EditorIconButton: View {
    let symbol: String
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.ink.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .editorEnabled(enabled)
        .accessibilityLabel(label)
    }
}

struct EditorTogglePill: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { action() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(title).lineLimit(1)
            }
            .font(KFont.ui(14.5, .semibold, relativeTo: .subheadline))
            .foregroundStyle(isOn ? Palette.onGold : Palette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(isOn ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct EditorStepRow: View {
    let title: String
    let value: String
    var canMinus = true
    var canPlus = true
    var last = false
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Text(value)
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            EditorIconButton(symbol: "minus", label: "Less: \(title)", enabled: canMinus, action: minus)
            EditorIconButton(symbol: "plus", label: "More: \(title)", enabled: canPlus, action: plus)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 16) }
        }
        .accessibilityElement(children: .contain)
    }
}

struct EditorSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let text: String
    var last = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Spacer()
                Text(text)
                    .font(KFont.ui(15))
                    .foregroundStyle(Palette.inkFaint)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .tint(Palette.gold)
                .accessibilityLabel(title)
                .accessibilityValue(text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 16) }
        }
    }
}

struct EditorRemoveRow: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            PillButton(title: "Remove", symbol: "minus.circle", danger: true, action: action)
        }
        .padding(10)
    }
}
