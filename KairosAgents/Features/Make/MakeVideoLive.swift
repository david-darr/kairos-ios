import SwiftUI

// The paired desktop behind the video editor (routes/video_routes.py): open a video by its id, edit it, save it
// with the version it was filled from, render it, ask Kairos, narrate it and restore an older version.
// Unpaired, nothing here runs and the editor is the sample editor.
//
// How a save works (this is the screen's form with revisions):
// - The editor remembers the desktop project it was FILLED from (`doc`, with its `version`) and that project as the
//   editor's own state (`filled`). What the person changed is the difference between `state` and `filled`.
// - A save sends the filled project with only that difference applied on top (`MakeVideoCodec.body`), with the
//   filled version. Fields and parts the phone does not edit (spoken lines, cast, tracks it does not show) go back
//   exactly as they came.
// - A re-read (a 409, a lost answer, coming back to the front) is rebuilt on top of the person's edits
//   (`MakeVideoCodec.rebase`): a field the person did not change follows the desktop, a field they changed stays
//   theirs, and the next save carries only those fields on the new version.
// - Beats, clips, tracks and comments are known by the desktop's own text ids. The editor's drawing code uses
//   whole numbers, so `MakeVideoIDs` hands each desktop id one number for the life of the screen and back.

// MARK: - Ids

/// One whole number per desktop id, for as long as the screen lives, and the way back. A beat or clip the person
/// makes gets a number from 1,000,000 up and a desktop id of its own the moment it is made.
nonisolated final class MakeVideoIDs {
    static let firstNew = 1_000_000

    private var handles: [String: Int] = [:]
    private var names: [Int: String] = [:]
    private var copies: [Int: Int] = [:]
    private var counter = 0
    private var trackID: String?
    private(set) var taken: Set<String> = []
    /// The highest number handed to a beat or clip the person made. New numbers always go above it.
    private(set) var highestMinted = MakeVideoIDs.firstNew - 1
    private var beatSnapshots: [Int: (raw: [String: Any], filled: EditorBeat)] = [:]

    func handle(_ scope: String, _ id: String) -> Int {
        let key = scope + ":" + id
        if let found = handles[key] { return found }
        counter += 1
        handles[key] = counter
        names[counter] = id
        return counter
    }

    func desktopID(_ handle: Int) -> String? { names[handle] }

    /// Every beat, track and clip id the desktop holds, so a new id never repeats one.
    func noteTaken(_ doc: MakeVideoDoc) {
        for beat in doc.beats {
            if let id = MakeVideoWire.str(beat["id"]) { taken.insert(id) }
        }
        for track in doc.tracks {
            if let id = MakeVideoWire.str(track["id"]) { taken.insert(id) }
            for clip in MakeVideoWire.dicts(track["clips"]) {
                if let id = MakeVideoWire.str(clip["id"]) { taken.insert(id) }
            }
        }
    }

    /// The desktop id for a beat or clip the person just made, kept for the life of the screen.
    func mint(_ scope: String, prefix: String, handle: Int) -> String {
        var id = prefix + String(handle, radix: 36)
        while taken.contains(id) { id += "x" }
        taken.insert(id)
        handles[scope + ":" + id] = handle
        names[handle] = id
        if handle >= MakeVideoIDs.firstNew { highestMinted = max(highestMinted, handle) }
        return id
    }

    /// The number the next new beat or clip gets: above every number in use.
    var nextNew: Int { max(MakeVideoIDs.firstNew, highestMinted + 1) }

    /// Keep a copy of the beat a duplicate was made from, as the desktop held it then, so the duplicate can still be
    /// saved if the desktop later deletes the original.
    func snapshotBeat(copy handle: Int, of source: Int, doc: MakeVideoDoc?, filled: EditorState) {
        if let did = desktopID(source),
           let raw = doc?.beats.first(where: { MakeVideoWire.str($0["id"]) == did }),
           let was = filled.beats.first(where: { $0.id == source }) {
            beatSnapshots[handle] = (raw, was)
        } else if let inherited = beatSnapshots[source] {
            beatSnapshots[handle] = inherited
        }
    }

    func beatSnapshot(_ handle: Int) -> (raw: [String: Any], filled: EditorBeat)? { beatSnapshots[handle] }

    /// An overlay track the person adds when the video has none.
    func newTrackID() -> String {
        if let trackID { return trackID }
        let id = mint("track", prefix: "ov", handle: 0)
        trackID = id
        return id
    }

    func setCopy(_ handle: Int, from source: Int) { copies[handle] = source }

    func copySource(_ handle: Int) -> Int? { copies[handle] }
}

// MARK: - The project and the editor's state

extension EditorState {
    /// Same beats, clips and track flags. `nextID` is only a counter.
    nonisolated func sameContent(_ other: EditorState) -> Bool {
        beats == other.beats && clips == other.clips && trackHidden == other.trackHidden
            && trackLocked == other.trackLocked && trackRemoved == other.trackRemoved
    }
}

nonisolated struct MakeVideoMerge {
    var state: EditorState
    /// Edits of the person's that no longer apply (the desktop removed the beat or clip they changed).
    var dropped: Int
}

/// Turning the desktop's project into the editor's state, the editor's state back into a project, and keeping
/// the person's edits when the desktop's project moves on. No state of its own.
nonisolated enum MakeVideoCodec {

    // MARK: Words the editor shows and the desktop's own names for them

    static let colours: [(desktop: String, phone: String)] = [
        ("text", "Text"), ("dim", "Soft text"), ("accent", "Accent"), ("accent-2", "Second accent"),
        ("bg", "Background"), ("surface", "Surface"), ("white", "White"), ("black", "Black"),
    ]
    static let shapes: [(desktop: String, phone: String)] = [
        ("rect", "Rectangle"), ("ellipse", "Ellipse"), ("line", "Line"), ("arrow", "Arrow"),
    ]
    static let keyProps: [(desktop: String, phone: String)] = [
        ("x", "Left"), ("y", "Top"), ("scale", "Size"), ("rotation", "Turn"), ("opacity", "Opacity"),
    ]

    static func colourName(_ desktop: String?) -> String { colours.first { $0.desktop == desktop }?.phone ?? "Text" }
    static func colourKey(_ phone: String) -> String { colours.first { $0.phone == phone }?.desktop ?? "text" }
    static func shapeName(_ desktop: String?) -> String { shapes.first { $0.desktop == desktop }?.phone ?? "Rectangle" }
    static func shapeKey(_ phone: String) -> String { shapes.first { $0.phone == phone }?.desktop ?? "rect" }

    static func overlayTrack(_ doc: MakeVideoDoc) -> [String: Any]? {
        doc.tracks.first { MakeVideoWire.str($0["kind"]) == "overlay" }
    }

    static func overlayTrackID(_ doc: MakeVideoDoc) -> String? {
        overlayTrack(doc).flatMap { MakeVideoWire.str($0["id"]) }
    }

    /// Tracks the phone does not show: sound tracks and overlays after the first.
    static func otherTracks(_ doc: MakeVideoDoc) -> Int {
        let shown = overlayTrackID(doc)
        return doc.tracks.filter { MakeVideoWire.str($0["id"]) != shown }.count
    }

    // MARK: Project to state

    static func state(_ doc: MakeVideoDoc, ids: MakeVideoIDs) -> EditorState {
        ids.noteTaken(doc)
        let bpm = doc.bpm
        let beats = doc.beats.compactMap { beat($0, bpm: bpm, ids: ids) }
        var clips: [EditorClip] = []
        var hidden = false
        var locked = false
        var removed = true
        if let track = overlayTrack(doc) {
            removed = false
            hidden = MakeVideoWire.bool(track["hidden"]) ?? false
            locked = MakeVideoWire.bool(track["locked"]) ?? false
            clips = MakeVideoWire.dicts(track["clips"]).compactMap { clip($0, ids: ids) }
        }
        return EditorState(beats: beats, clips: clips, trackHidden: hidden, trackLocked: locked, trackRemoved: removed,
                           nextID: ids.nextNew)
    }

    static func chapters(_ doc: MakeVideoDoc, ids: MakeVideoIDs) -> [(beat: Int, title: String)] {
        doc.chapters.compactMap { chapter in
            guard let start = MakeVideoWire.str(chapter["start"]), let title = MakeVideoWire.str(chapter["title"]) else { return nil }
            return (ids.handle("beat", start), title)
        }
    }

    static func beat(_ raw: [String: Any], bpm: Double, ids: MakeVideoIDs) -> EditorBeat? {
        guard let did = MakeVideoWire.str(raw["id"]) else { return nil }
        let kindText = MakeVideoWire.str(raw["kind"]) ?? "statement"
        let say = MakeVideoWire.str(raw["say"])
        let measured = MakeVideoWire.num(raw["seconds"])
        let kind: EditorBeatKind
        switch kindText {
        case "scene": kind = .scene
        case "story": kind = .story
        case "stage": kind = .stage
        case "voxel": kind = .blocky
        default: kind = .card
        }
        var b = EditorBeat(id: ids.handle("beat", did), kind: kind, caption: say ?? MakeVideoWire.str(raw["text"]) ?? "",
                           narrated: say != nil || measured != nil, seconds: measured ?? 2, bars: MakeVideoWire.num(raw["bars"]) ?? 1)
        b.rawKind = kindText
        b.captionField = say != nil ? "say" : "text"
        b.barSeconds = 240 / max(60, bpm)
        switch kind {
        case .scene:
            let scene = raw["scene"] as? [String: Any] ?? [:]
            b.setting = MakeVideoWire.str(scene["setting"]) ?? "meadow"
            b.shot = MakeVideoWire.str(scene["shot"]) ?? "medium"
            b.characters = MakeVideoWire.dicts(scene["cast"]).enumerated().map { index, member in
                var character = EditorCharacter(
                    id: ids.handle("cast", did + "#" + (MakeVideoWire.str(member["character"]) ?? "\(index)")),
                    name: "Cast \(index + 1)", position: (MakeVideoWire.num(member["x"]) ?? 0.5) * 100)
                character.expression = MakeVideoWire.str(member["expression"]) ?? "neutral"
                character.action = MakeVideoWire.str(member["action"]) ?? "idle"
                character.speaks = MakeVideoWire.bool(member["speaking"]) ?? false
                return character
            }
            b.props = MakeVideoWire.dicts(scene["props"]).enumerated().map { index, prop in
                EditorProp(id: index + 1, icon: MakeVideoWire.str(prop["icon"]) ?? "star",
                           across: (MakeVideoWire.num(prop["x"]) ?? 0.5) * 100, size: (MakeVideoWire.num(prop["size"]) ?? 0.1) * 100,
                           floats: MakeVideoWire.bool(prop["float"]) ?? false)
            }
        case .story:
            let story = raw["story"] as? [String: Any] ?? [:]
            b.place = MakeVideoWire.str(story["place"]) ?? "meadow"
            b.timeOfDay = MakeVideoWire.str(story["time"]) ?? "day"
            b.gap = MakeVideoWire.num(raw["gap"]) ?? 0.4
            b.flashback = MakeVideoWire.bool(raw["flashback"]) ?? false
            b.keyWords = MakeVideoWire.strings(story["keys"]).joined(separator: ", ")
            let shots = MakeVideoWire.dicts(story["shots"]).compactMap { MakeVideoWire.str($0["shot"]) }
            b.shots = shots.isEmpty ? ["medium"] : shots
            b.speaker = "Speaker"
        case .stage:
            let stage = raw["stage"] as? [String: Any] ?? [:]
            b.world = MakeVideoWire.str(stage["set"]) ?? "lavender"
            b.shot = MakeVideoWire.str(stage["shot"]) ?? "medium"
            b.pedestal = MakeVideoWire.bool(stage["pedestal"]) ?? false
        case .blocky:
            let voxel = raw["voxel"] as? [String: Any] ?? [:]
            b.world = MakeVideoWire.str(voxel["world"]) ?? "meadow"
            b.timeOfDay = MakeVideoWire.str(voxel["time"]) ?? "day"
            b.shot = MakeVideoWire.str(voxel["shot"]) ?? "medium"
        case .card:
            break
        }
        return b
    }

    static func clip(_ raw: [String: Any], ids: MakeVideoIDs) -> EditorClip? {
        guard let did = MakeVideoWire.str(raw["id"]) else { return nil }
        let kind: EditorClipKind
        switch MakeVideoWire.str(raw["kind"]) {
        case "text"?: kind = .text
        case "shape"?: kind = .shape
        case "image"?: kind = .image
        case "video"?: kind = .video
        default: return nil
        }
        let source = MakeVideoWire.num(raw["in"]) ?? 0
        let out = MakeVideoWire.num(raw["out"]) ?? (source + 1)
        var c = EditorClip(id: ids.handle("clip", did), kind: kind, start: MakeVideoWire.num(raw["start"]) ?? 0,
                           length: max(1.0 / 30, out - source))
        c.source = source
        c.opacity = MakeVideoWire.num(raw["opacity"]) ?? 1
        c.fadeIn = MakeVideoWire.num(raw["fade_in"]) ?? 0
        c.fadeOut = MakeVideoWire.num(raw["fade_out"]) ?? 0
        let box = raw["box"] as? [String: Any]
        c.left = (MakeVideoWire.num(box?["x"]) ?? 0.1) * 100
        c.top = (MakeVideoWire.num(box?["y"]) ?? 0.1) * 100
        c.width = (MakeVideoWire.num(box?["w"]) ?? 0.8) * 100
        c.height = (MakeVideoWire.num(box?["h"]) ?? 0.12) * 100
        switch kind {
        case .text:
            c.text = MakeVideoWire.str(raw["text"]) ?? ""
            c.size = MakeVideoWire.str(raw["role"]) == "body" ? "Body" : "Headline"
            c.style = MakeVideoWire.str(raw["style"]) == "plain" ? "Plain" : "On a card"
            c.colour = colourName(MakeVideoWire.str(raw["color"]))
            switch MakeVideoWire.str(raw["align"]) {
            case "left"?: c.align = "Left"
            case "right"?: c.align = "Right"
            default: c.align = "Center"
            }
        case .shape:
            c.shape = shapeName(MakeVideoWire.str(raw["shape"]))
            c.colour = colourName(MakeVideoWire.str(raw["color"]))
            c.filled = MakeVideoWire.bool(raw["fill"]) ?? true
        case .image, .video:
            break
        }
        if let keys = raw["keys"] as? [String: Any] {
            var times: Set<Double> = []
            for (prop, list) in keys {
                guard let name = keyProps.first(where: { $0.desktop == prop })?.phone else { continue }
                c.animated.insert(name)
                for key in MakeVideoWire.dicts(list) {
                    if let t = MakeVideoWire.num(key["t"]) { times.insert(MakeVideoWire.round4(t - source)) }
                }
            }
            c.keyTimes = times.sorted()
        }
        return c
    }

    // MARK: State to project

    private static func put<T: Equatable>(_ raw: inout [String: Any], _ section: String, _ key: String, _ new: T, _ old: T) {
        guard new != old else { return }
        var inner = raw[section] as? [String: Any] ?? [:]
        inner[key] = new
        raw[section] = inner
    }

    /// The beat's project object with the fields the person changed (`e` against `f`, what it was filled from).
    static func apply(_ e: EditorBeat, over f: EditorBeat, to raw: inout [String: Any]) {
        if e.caption != f.caption { raw[e.captionField] = e.caption }
        if !e.narrated, abs(e.bars - f.bars) > 0.0001 { raw["bars"] = e.bars }
        switch e.kind {
        case .scene:
            put(&raw, "scene", "setting", e.setting, f.setting)
            put(&raw, "scene", "shot", e.shot, f.shot)
        case .stage:
            put(&raw, "stage", "set", e.world, f.world)
            put(&raw, "stage", "shot", e.shot, f.shot)
            put(&raw, "stage", "pedestal", e.pedestal, f.pedestal)
        case .blocky:
            put(&raw, "voxel", "world", e.world, f.world)
            put(&raw, "voxel", "time", e.timeOfDay, f.timeOfDay)
            put(&raw, "voxel", "shot", e.shot, f.shot)
        case .story:
            put(&raw, "story", "place", e.place, f.place)
            put(&raw, "story", "time", e.timeOfDay, f.timeOfDay)
            if e.flashback != f.flashback { raw["flashback"] = e.flashback }
            if abs(e.gap - f.gap) > 0.0001, raw["say"] != nil { raw["gap"] = MakeVideoWire.round4(e.gap) }
        case .card:
            break
        }
    }

    private static func same(_ a: Double, _ b: Double, _ tolerance: Double = 0.0005) -> Bool { abs(a - b) <= tolerance }

    static func apply(_ e: EditorClip, over f: EditorClip, to raw: inout [String: Any]) {
        switch e.kind {
        case .text:
            if e.text != f.text { raw["text"] = e.text }
            if e.size != f.size { raw["role"] = e.size == "Body" ? "body" : "title" }
            if e.style != f.style { raw["style"] = e.style == "Plain" ? "plain" : "card" }
            if e.colour != f.colour { raw["color"] = colourKey(e.colour) }
            if e.align != f.align { raw["align"] = e.align.lowercased() }
        case .shape:
            if e.shape != f.shape { raw["shape"] = shapeKey(e.shape) }
            if e.colour != f.colour { raw["color"] = colourKey(e.colour) }
            if e.filled != f.filled { raw["fill"] = e.filled }
        case .image, .video:
            break
        }
        if !same(e.start, f.start) || !same(e.length, f.length) || !same(e.source, f.source) {
            raw["start"] = MakeVideoWire.round4(e.start)
            raw["in"] = MakeVideoWire.round4(e.source)
            raw["out"] = MakeVideoWire.round4(e.source + e.length)
        }
        if !same(e.fadeIn, f.fadeIn) { raw["fade_in"] = MakeVideoWire.round4(e.fadeIn) }
        if !same(e.fadeOut, f.fadeOut) { raw["fade_out"] = MakeVideoWire.round4(e.fadeOut) }
        if !same(e.opacity, f.opacity) { raw["opacity"] = MakeVideoWire.round4(e.opacity) }
        if !same(e.left, f.left) || !same(e.top, f.top) || !same(e.width, f.width) || !same(e.height, f.height) {
            raw["box"] = ["x": MakeVideoWire.round4(e.left / 100), "y": MakeVideoWire.round4(e.top / 100),
                          "w": MakeVideoWire.round4(e.width / 100), "h": MakeVideoWire.round4(e.height / 100)]
        }
    }

    /// A text or shape clip the person added: every field the desktop needs.
    static func newClip(_ e: EditorClip, id: String) -> [String: Any] {
        var raw: [String: Any] = [
            "id": id, "kind": e.kind == .text ? "text" : "shape",
            "start": MakeVideoWire.round4(e.start), "in": MakeVideoWire.round4(e.source),
            "out": MakeVideoWire.round4(e.source + e.length),
            "opacity": MakeVideoWire.round4(e.opacity), "fade_in": MakeVideoWire.round4(e.fadeIn), "fade_out": MakeVideoWire.round4(e.fadeOut),
            "box": ["x": MakeVideoWire.round4(e.left / 100), "y": MakeVideoWire.round4(e.top / 100),
                    "w": MakeVideoWire.round4(e.width / 100), "h": MakeVideoWire.round4(e.height / 100)],
        ]
        if e.kind == .text {
            raw["text"] = e.text
            raw["role"] = e.size == "Body" ? "body" : "title"
            raw["style"] = e.style == "Plain" ? "plain" : "card"
            raw["color"] = colourKey(e.colour)
            raw["align"] = e.align.lowercased()
        } else {
            raw["shape"] = shapeKey(e.shape)
            raw["color"] = colourKey(e.colour)
            raw["fill"] = e.filled
            raw["stroke"] = 0.006
        }
        return raw
    }

    /// The nearest earlier thing this one was copied from that the desktop already holds, with its project object.
    private static func copyRoot(_ handle: Int, ids: MakeVideoIDs, known: [String: [String: Any]]) -> (handle: Int, raw: [String: Any])? {
        var current = handle
        var hops = 0
        while hops < 50, let parent = ids.copySource(current) {
            current = parent
            hops += 1
            if let did = ids.desktopID(current), let raw = known[did] { return (current, raw) }
        }
        return nil
    }

    /// The project to send: the project the editor was filled from, with the person's changes (`mine` against
    /// `filled`) applied on top, and the version it was filled from. Nothing the person did not touch is changed.
    static func body(base: MakeVideoDoc, filled: EditorState, mine: EditorState, ids: MakeVideoIDs) -> [String: Any] {
        var raw = base.raw
        for key in MakeVideoDoc.metaKeys { raw.removeValue(forKey: key) }

        var beatsByID: [String: [String: Any]] = [:]
        for beat in base.beats {
            if let id = MakeVideoWire.str(beat["id"]) { beatsByID[id] = beat }
        }
        let filledBeats = Dictionary(filled.beats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var beats: [[String: Any]] = []
        for beat in mine.beats {
            guard let did = ids.desktopID(beat.id) else { continue }
            if var existing = beatsByID[did] {
                apply(beat, over: filledBeats[beat.id] ?? beat, to: &existing)
                beats.append(existing)
            } else if let root = copyRoot(beat.id, ids: ids, known: beatsByID), let from = filledBeats[root.handle] {
                var copy = root.raw
                copy["id"] = did
                apply(beat, over: from, to: &copy)
                beats.append(copy)
            } else if let snap = ids.beatSnapshot(beat.id) {
                // The beat it was copied from is gone from the desktop: save from the copy kept when it was made.
                var copy = snap.raw
                copy["id"] = did
                apply(beat, over: snap.filled, to: &copy)
                beats.append(copy)
            }
        }
        raw["beats"] = beats

        var tracks = base.tracks
        let trackID = overlayTrackID(base)
        if let trackID, let index = tracks.firstIndex(where: { MakeVideoWire.str($0["id"]) == trackID }) {
            var track = tracks[index]
            var clipsByID: [String: [String: Any]] = [:]
            for clip in MakeVideoWire.dicts(track["clips"]) {
                if let id = MakeVideoWire.str(clip["id"]) { clipsByID[id] = clip }
            }
            track["clips"] = clipObjects(mine: mine, filled: filled, known: clipsByID, ids: ids)
            if mine.trackHidden != filled.trackHidden { track["hidden"] = mine.trackHidden }
            if mine.trackLocked != filled.trackLocked { track["locked"] = mine.trackLocked }
            tracks[index] = track
        } else if !mine.trackRemoved {
            // The video had no overlay track and the person added one.
            let track: [String: Any] = [
                "id": ids.newTrackID(), "kind": "overlay", "name": "Overlay",
                "hidden": mine.trackHidden, "locked": mine.trackLocked,
                "clips": clipObjects(mine: mine, filled: filled, known: [:], ids: ids),
            ]
            tracks.append(track)
        }
        if tracks.isEmpty {
            raw.removeValue(forKey: "tracks")
        } else {
            raw["tracks"] = tracks
        }
        raw["version"] = base.version
        return raw
    }

    private static func clipObjects(mine: EditorState, filled: EditorState, known: [String: [String: Any]], ids: MakeVideoIDs) -> [[String: Any]] {
        let filledClips = Dictionary(filled.clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [[String: Any]] = []
        for clip in mine.clips {
            guard let did = ids.desktopID(clip.id) else { continue }
            if var existing = known[did] {
                apply(clip, over: filledClips[clip.id] ?? clip, to: &existing)
                out.append(existing)
            } else if let root = copyRoot(clip.id, ids: ids, known: known), let from = filledClips[root.handle] {
                var copy = root.raw
                copy["id"] = did
                apply(clip, over: from, to: &copy)
                out.append(copy)
            } else if clip.kind == .text || clip.kind == .shape {
                out.append(newClip(clip, id: did))
            }
        }
        return out
    }

    // MARK: Keeping the person's edits when the desktop's project moves on

    private static func keep<T, V: Equatable>(_ path: WritableKeyPath<T, V>, _ base: T, _ mine: T, _ out: inout T) {
        if mine[keyPath: path] != base[keyPath: path] { out[keyPath: path] = mine[keyPath: path] }
    }

    static func mergeBeat(base: EditorBeat, theirs: EditorBeat, mine: EditorBeat) -> EditorBeat {
        var out = theirs
        keep(\EditorBeat.caption, base, mine, &out)
        keep(\EditorBeat.bars, base, mine, &out)
        keep(\EditorBeat.setting, base, mine, &out)
        keep(\EditorBeat.shot, base, mine, &out)
        keep(\EditorBeat.world, base, mine, &out)
        keep(\EditorBeat.timeOfDay, base, mine, &out)
        keep(\EditorBeat.place, base, mine, &out)
        keep(\EditorBeat.pedestal, base, mine, &out)
        keep(\EditorBeat.flashback, base, mine, &out)
        keep(\EditorBeat.gap, base, mine, &out)
        return out
    }

    static func mergeClip(base: EditorClip, theirs: EditorClip, mine: EditorClip) -> EditorClip {
        var out = theirs
        keep(\EditorClip.text, base, mine, &out)
        keep(\EditorClip.size, base, mine, &out)
        keep(\EditorClip.style, base, mine, &out)
        keep(\EditorClip.colour, base, mine, &out)
        keep(\EditorClip.align, base, mine, &out)
        keep(\EditorClip.shape, base, mine, &out)
        keep(\EditorClip.filled, base, mine, &out)
        keep(\EditorClip.start, base, mine, &out)
        keep(\EditorClip.length, base, mine, &out)
        keep(\EditorClip.source, base, mine, &out)
        keep(\EditorClip.fadeIn, base, mine, &out)
        keep(\EditorClip.fadeOut, base, mine, &out)
        keep(\EditorClip.opacity, base, mine, &out)
        keep(\EditorClip.left, base, mine, &out)
        keep(\EditorClip.top, base, mine, &out)
        keep(\EditorClip.width, base, mine, &out)
        keep(\EditorClip.height, base, mine, &out)
        return out
    }

    /// The desktop's newer project (`theirs`) with the person's edits (`mine` against `base`, the project they
    /// were made on) kept on top. A field the person did not change takes the desktop's value, so nothing the
    /// person left alone looks edited and no old value is sent again.
    static func rebase(base: EditorState, theirs: EditorState, mine: EditorState) -> MakeVideoMerge {
        var dropped = 0

        // Beats
        let baseBeats = Dictionary(base.beats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let theirBeats = Dictionary(theirs.beats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let myBeats = Dictionary(mine.beats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let deletedBeats = Set(base.beats.map(\.id)).subtracting(mine.beats.map(\.id))
        let myOrder = mine.beats.map(\.id).filter { baseBeats[$0] != nil }
        let baseOrder = base.beats.map(\.id).filter { !deletedBeats.contains($0) }
        var order: [Int]
        if myOrder != baseOrder {
            // The person moved beats: their order stays, and a beat the desktop added goes at the end.
            order = myOrder.filter { theirBeats[$0] != nil } + theirs.beats.map(\.id).filter { baseBeats[$0] == nil }
        } else {
            order = theirs.beats.map(\.id).filter { !deletedBeats.contains($0) }
        }
        for (index, beat) in mine.beats.enumerated() where baseBeats[beat.id] == nil {
            var place = 0
            var back = index - 1
            while back >= 0 {
                if let found = order.firstIndex(of: mine.beats[back].id) {
                    place = found + 1
                    break
                }
                back -= 1
            }
            order.insert(beat.id, at: min(place, order.count))
        }
        var beats: [EditorBeat] = []
        for id in order {
            if let theirsBeat = theirBeats[id] {
                if let baseBeat = baseBeats[id], let myBeat = myBeats[id] {
                    beats.append(mergeBeat(base: baseBeat, theirs: theirsBeat, mine: myBeat))
                } else {
                    beats.append(theirsBeat)
                }
            } else if baseBeats[id] == nil, let myBeat = myBeats[id] {
                beats.append(myBeat)
            }
        }
        for (id, baseBeat) in baseBeats where theirBeats[id] == nil {
            if let myBeat = myBeats[id], mergeBeat(base: baseBeat, theirs: baseBeat, mine: myBeat) != baseBeat { dropped += 1 }
        }

        // Clips
        let baseClips = Dictionary(base.clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let theirClips = Dictionary(theirs.clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let myClips = Dictionary(mine.clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let deletedClips = Set(base.clips.map(\.id)).subtracting(mine.clips.map(\.id))
        var clips: [EditorClip] = []
        for theirsClip in theirs.clips where !deletedClips.contains(theirsClip.id) {
            if let baseClip = baseClips[theirsClip.id], let myClip = myClips[theirsClip.id] {
                clips.append(mergeClip(base: baseClip, theirs: theirsClip, mine: myClip))
            } else {
                clips.append(theirsClip)
            }
        }
        for myClip in mine.clips where baseClips[myClip.id] == nil && theirClips[myClip.id] == nil {
            clips.append(myClip)
        }
        for (id, baseClip) in baseClips where theirClips[id] == nil {
            if let myClip = myClips[id], mergeClip(base: baseClip, theirs: baseClip, mine: myClip) != baseClip { dropped += 1 }
        }
        clips.sort { ($0.start, $0.id) < ($1.start, $1.id) }

        var out = EditorState(beats: beats, clips: clips, trackHidden: theirs.trackHidden, trackLocked: theirs.trackLocked,
                              trackRemoved: theirs.trackRemoved, nextID: max(mine.nextID, theirs.nextID))
        if mine.trackHidden != base.trackHidden { out.trackHidden = mine.trackHidden }
        if mine.trackLocked != base.trackLocked { out.trackLocked = mine.trackLocked }
        if mine.trackRemoved != base.trackRemoved, theirs.trackRemoved { out.trackRemoved = mine.trackRemoved }
        return MakeVideoMerge(state: out, dropped: dropped)
    }

    // MARK: Comparing the desktop with what was sent

    /// The desktop's project now holds what was sent: the same beats in the same order and the same values in
    /// every field the phone edits, and the same clips.
    static func matches(sent: EditorState, desktop: EditorState) -> Bool {
        guard sent.beats.map(\.id) == desktop.beats.map(\.id),
              sent.clips.map(\.id).sorted() == desktop.clips.map(\.id).sorted(),
              sent.trackHidden == desktop.trackHidden, sent.trackLocked == desktop.trackLocked,
              sent.trackRemoved == desktop.trackRemoved else { return false }
        for (a, b) in zip(sent.beats, desktop.beats) {
            guard a.caption == b.caption, (a.narrated || same(a.bars, b.bars)), a.setting == b.setting, a.shot == b.shot,
                  a.world == b.world, a.timeOfDay == b.timeOfDay, a.place == b.place, a.pedestal == b.pedestal,
                  a.flashback == b.flashback, same(a.gap, b.gap, 0.001) else { return false }
        }
        let desktopClips = Dictionary(desktop.clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for a in sent.clips {
            guard let b = desktopClips[a.id], a.text == b.text, a.size == b.size, a.style == b.style, a.colour == b.colour,
                  a.align == b.align, a.shape == b.shape, a.filled == b.filled, same(a.start, b.start, 0.002),
                  same(a.length, b.length, 0.002), same(a.fadeIn, b.fadeIn, 0.002), same(a.fadeOut, b.fadeOut, 0.002),
                  same(a.opacity, b.opacity, 0.002), same(a.left, b.left, 0.02), same(a.top, b.top, 0.02),
                  same(a.width, b.width, 0.02), same(a.height, b.height, 0.02) else { return false }
        }
        return true
    }
}

// MARK: - What the person had not saved when they left

nonisolated struct MakeVideoDraft {
    var state: EditorState
    var filled: EditorState
    var ids: MakeVideoIDs
    /// The desktop's version the draft was made on.
    var version: Int
}

/// Unsaved edits kept in memory when the person leaves a video without saving (a swipe back, a tab change), and
/// handed back when the same video is opened again on the same desktop and account.
enum MakeVideoDrafts {
    private static var kept: [String: MakeVideoDraft] = [:]

    static func put(_ draft: MakeVideoDraft, account: String, video: String) { kept[account + "|" + video] = draft }
    static func take(account: String, video: String) -> MakeVideoDraft? { kept.removeValue(forKey: account + "|" + video) }
    static func drop(account: String, video: String) { kept.removeValue(forKey: account + "|" + video) }
}

/// An Ask whose answer never arrived: when it was sent, which runs existed before it, and its (stripped) text.
nonisolated struct MakeVideoAskPending {
    var since: Date
    var before: Set<String>
    var request: String
}

/// The unconfirmed Ask, kept in memory next to the drafts so closing and reopening the video never turns Ask back
/// on. Cleared only when that Ask's own run is seen or when the person confirms "Ask again anyway", never on unpair.
enum MakeVideoAskStore {
    private static var kept: [String: MakeVideoAskPending] = [:]

    static func put(_ pending: MakeVideoAskPending, account: String, video: String) { kept[account + "|" + video] = pending }
    static func get(account: String, video: String) -> MakeVideoAskPending? { kept[account + "|" + video] }
    static func clear(account: String, video: String) { kept.removeValue(forKey: account + "|" + video) }
}

// MARK: - The live session

nonisolated enum MakeVideoPhase: Equatable, Sendable {
    case loading, ready, missing
    case failed(String)
}

/// Which one confirm sheet the editor shows.
nonisolated enum EditorConfirm: String, Hashable, Identifiable, Sendable {
    case render, stopRender, narrate, leave
    var id: String { rawValue }
}

/// Everything the editor knows about the paired desktop's copy of one video. One per open editor.
@Observable
final class MakeVideoLive {
    let videoID: String
    /// Which desktop and which account this belongs to. Nothing read from another one stays on screen.
    let account: String

    var phase: MakeVideoPhase = .loading
    /// The desktop's project this editor was filled from, with its version.
    var doc: MakeVideoDoc?
    /// That project as the editor's state. What the person changed is `state` against this.
    var filled = EditorState(beats: [], clips: [])
    var overlayTrackID: String?
    var otherTracks = 0
    var ids = MakeVideoIDs()
    var seconds: Double = 0

    // Saving
    var saving = false
    var saveProblem: String?
    /// Set when a save's or a restore's answer never arrived and the desktop could not be read to settle it.
    var unconfirmed: String?
    var notice: String?
    var checking = false

    // The history sheet
    var restoring = false

    // Render
    var job: MakeVideoJobDTO?
    var renderLine: String?
    var renderBusy = false
    var renderUnchecked = false
    var stopping = false
    var renderAspect = ""
    var jobsKnown = false

    // Narration
    var narrating = false
    var narrationLine: String?
    /// A narrate answer never arrived and no line is spoken yet: Narrate stays off until the desktop settles it.
    var narrateUnconfirmed = false
    var narrateChecking = false

    // Ask Kairos
    var review: MakeVideoReviewDTO?
    var askBusy = false
    var askLine: String?
    var askUnconfirmed = false
    /// 15 minutes passed since the lost request with no new run: asking again is possible, through a confirm.
    var askMayRepeat = false
    var askChecking = false
    var latestRun: MakeVideoRunDTO?

    @ObservationIgnored var readSerial = 0
    @ObservationIgnored var writeSerial = 0
    @ObservationIgnored var watchTask: Task<Void, Never>?
    @ObservationIgnored var pendingDraft: MakeVideoDraft?
    @ObservationIgnored var pendingSent: (state: EditorState, version: Int)?
    @ObservationIgnored var knownJobs: Set<String> = []
    @ObservationIgnored var knownRuns: Set<String> = []
    @ObservationIgnored var narrateMissing = 0
    @ObservationIgnored var askSince: Date?
    /// The run ids that existed before the unconfirmed Ask was sent, and its stripped text.
    @ObservationIgnored var askBefore: Set<String> = []
    @ObservationIgnored var askRequest = ""
    @ObservationIgnored var askWatchTask: Task<Void, Never>?
    @ObservationIgnored var restoreFrom: Int?
    /// The person chose to leave without saving: nothing is kept for next time.
    @ObservationIgnored var abandoned = false

    init(videoID: String) {
        self.videoID = videoID
        account = MakeVideoLive.accountKey
    }

    /// The start of the line shown when a re-read failed. A later successful read clears it.
    static let unreadPrefix = "Your desktop could not be read"

    /// Which desktop and which account the live video belongs to, or "sample".
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// This Ask is settled: its run was seen, or the person confirmed asking again.
    func clearAsk() {
        askUnconfirmed = false
        askMayRepeat = false
        askSince = nil
        askBefore = []
        askRequest = ""
        MakeVideoAskStore.clear(account: account, video: videoID)
    }

    /// A key that changes when the phone is paired or unpaired, the desktop comes back, or another desktop or
    /// account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }
}

// MARK: - The editor on the paired desktop

extension EditorModel {

    var isLive: Bool { live != nil }

    /// The screen shows the editor: the sample, or a live video that has been read.
    var showsEditor: Bool { live == nil || live?.phase == .ready }

    /// The person has changed something that is not on the desktop yet.
    var isDirty: Bool {
        guard let live, live.phase == .ready else { return false }
        return !state.sameContent(live.filled)
    }

    var canSaveLive: Bool {
        guard let live, live.phase == .ready else { return false }
        return isDirty && !live.saving && live.unconfirmed == nil && !live.restoring && !live.checking && live.pendingSent == nil
    }

    /// A long video's chapters point at beats, so adding, moving and removing beats stays on the desktop.
    var structureLocked: Bool { live?.doc?.isChaptered == true }

    static let structureLine = "Beats can't be added, moved or removed in a long video here. Do that on your desktop."

    func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    func stillLive(_ live: MakeVideoLive) -> Bool {
        self.live === live && !Connection.shared.usesSampleData && live.account == MakeVideoLive.accountKey
    }

    /// Refused by the desktop, which certainly did not act on it. Anything else (not reached, timed out, an
    /// answer this app could not read, a server error) may have come after it did.
    static func wasRefused(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status)
        case .offline, .unreadable: return false
        }
    }

    private static func statusOf(_ error: Error) -> Int? {
        if case .server(let status, _)? = error as? APIError { return status }
        return nil
    }

    private static func serverText(_ error: Error) -> String {
        if case .server(_, let detail)? = error as? APIError, !detail.isEmpty { return detail }
        return error.plainWords
    }

    // MARK: Opening

    /// Move between the sample editor and the paired desktop's video to match the connection, and read it.
    func follow() async {
        if Connection.shared.usesSampleData {
            if live != nil { leaveLive() }
            return
        }
        if live == nil || live?.account != MakeVideoLive.accountKey { enterLive() }
        guard let live else { return }
        let first = live.doc == nil
        await loadLive()
        guard stillLive(live), live.phase == .ready else { return }
        if first {
            await refreshReview()
            await adoptRunningJob()
            if live.askUnconfirmed, stillLive(live) {
                await checkAskLive(quiet: true)
                watchAsk()
            }
        }
    }

    func enterLive() {
        pause()
        live?.watchTask?.cancel()
        live?.askWatchTask?.cancel()
        playhead = 0
        selection = nil
        sheet = nil
        confirm = nil
        workIn = nil
        workOut = nil
        render = .idle
        let next = MakeVideoLive(videoID: projectID)
        if let draft = MakeVideoDrafts.take(account: next.account, video: projectID) {
            next.ids = draft.ids
            next.pendingDraft = draft
        }
        if let pending = MakeVideoAskStore.get(account: next.account, video: projectID) {
            next.askUnconfirmed = true
            next.askSince = pending.since
            next.askBefore = pending.before
            next.askRequest = pending.request
            next.askMayRepeat = Date().timeIntervalSince(pending.since) >= Self.askRepeatAfter
            next.askLine = "An earlier request to Kairos was not confirmed by your desktop. Ask stays off until its reply shows up."
        }
        live = next
        state = EditorState(beats: [], clips: [], nextID: next.ids.nextNew)
        comments = []
        chapters = []
        resetHistory()
    }

    func leaveLive() {
        live?.watchTask?.cancel()
        live?.askWatchTask?.cancel()
        live = nil
        confirm = nil
        sheet = nil
        selection = nil
        playhead = 0
        restoreSample()
        resetHistory()
    }

    /// Read the video from the desktop. Already read, what is on screen stays while it refreshes, and the
    /// person's edits are kept on top of whatever changed. Answers true when this read is what the screen shows.
    @discardableResult
    func loadLive() async -> Bool {
        guard let live else { return false }
        guard MakeVideoWire.isVideoID(projectID) else {
            live.phase = .missing
            return false
        }
        live.readSerial += 1
        let mine = live.readSerial
        if live.doc == nil { live.phase = .loading }
        for _ in 0..<3 {
            let writes = live.writeSerial
            do {
                let doc = try await liveClient().makeVideoGet(projectID)
                guard stillLive(live), mine == live.readSerial else { return false }
                // A read in flight never overwrites a write in flight.
                if live.saving || live.restoring { return false }
                guard writes == live.writeSerial else { continue }
                fill(from: doc, live: live, dropEdits: false)
                return true
            } catch {
                if error is CancellationError || Task.isCancelled { return false }
                Connection.shared.note(error)
                guard stillLive(live), mine == live.readSerial else { return false }
                if case .server(let status, _)? = error as? APIError, status == 404 {
                    live.doc = nil
                    live.phase = .missing
                } else if live.doc == nil {
                    live.phase = .failed("This video could not be read from your desktop. " + error.plainWords)
                } else {
                    live.renderLine = nil
                    live.saveProblem = MakeVideoLive.unreadPrefix + ". " + error.plainWords
                }
                return false
            }
        }
        if live.doc == nil { live.phase = .failed("This video kept changing while it was read. Try again.") }
        return false
    }

    /// Make the editor show this project. The person's edits stay on top unless `dropEdits`.
    func fill(from doc: MakeVideoDoc, live: MakeVideoLive, dropEdits: Bool) {
        // The document never moves backwards: a read older than the one on screen is ignored.
        if let current = live.doc?.version, doc.version < current { return }
        let filledNew = MakeVideoCodec.state(doc, ids: live.ids)
        var merged: MakeVideoMerge?
        var restored = false
        var draftDropped = false
        if let draft = live.pendingDraft {
            live.pendingDraft = nil
            if draft.version == doc.version {
                let result = MakeVideoCodec.rebase(base: draft.filled, theirs: filledNew, mine: draft.state)
                merged = result
                restored = !result.state.sameContent(filledNew)
            } else {
                // The desktop has a newer version than the one the draft was made on: never lay it over that.
                state = filledNew
                resetHistory()
                draftDropped = true
            }
        } else if live.doc == nil || dropEdits {
            state = filledNew
            resetHistory()
        } else if doc.version != live.doc?.version {
            merged = MakeVideoCodec.rebase(base: live.filled, theirs: filledNew, mine: state)
            resetHistory()
        }
        if let merged {
            state = merged.state
            if merged.dropped > 0 {
                live.notice = "Your desktop removed \(merged.dropped == 1 ? "something" : "\(merged.dropped) things") you had changed, so those changes are gone."
            } else if restored {
                live.notice = "Your unsaved changes from before are back."
            }
        }
        if draftDropped { live.notice = "This video changed on your desktop, so the unsaved edits from before were not kept." }
        // A successful read settles an earlier "could not be read" line.
        if live.saveProblem?.hasPrefix(MakeVideoLive.unreadPrefix) == true { live.saveProblem = nil }
        if live.narrateUnconfirmed, doc.unspokenLines < live.narrateMissing { live.narrateUnconfirmed = false }
        live.doc = doc
        live.filled = filledNew
        live.overlayTrackID = MakeVideoCodec.overlayTrackID(doc)
        live.otherTracks = MakeVideoCodec.otherTracks(doc)
        live.seconds = doc.seconds
        if live.renderAspect.isEmpty || !doc.aspects.contains(live.renderAspect) { live.renderAspect = doc.aspects.first ?? "16:9" }
        title = doc.title
        musicMood = doc.musicMood.capitalized
        fpsText = "\(doc.fps) fps"
        let aspectName = doc.aspects.first ?? "16:9"
        aspectText = aspectName
        let parts = aspectName.split(separator: ":").compactMap { Double($0) }
        aspectRatio = parts.count == 2 && parts[1] > 0 ? parts[0] / parts[1] : 9.0 / 16.0
        chapters = MakeVideoCodec.chapters(doc, ids: live.ids)
        live.phase = .ready
        if let selected = selection {
            switch selected {
            case .beat(let id): if index(of: id) == nil { selection = nil }
            case .clip(let id): if clipIndex(id) == nil { selection = nil }
            }
        }
        playhead = min(playhead, total)
    }

    // MARK: Making new things

    /// A new beat or clip gets its desktop id now, and for a copy, the one it was copied from.
    func liveMint(_ scope: String, prefix: String, handle: Int, copying source: Int? = nil) {
        guard let live else { return }
        _ = live.ids.mint(scope, prefix: prefix, handle: handle)
        if let source {
            live.ids.setCopy(handle, from: source)
            if scope == "beat" { live.ids.snapshotBeat(copy: handle, of: source, doc: live.doc, filled: live.filled) }
        }
    }

    // MARK: Saving

    private enum SaveResult {
        case saved(MakeVideoDoc)
        case changed
        case refused(String)
        case lost
    }

    /// Send the person's edits on top of the version they were made on. A second tap never sends again while
    /// one is on its way, nor after an answer that never arrived until the desktop has been read.
    func saveLive() async {
        guard let live, canSaveLive, let base = live.doc else { return }
        guard stillLive(live) else {
            live.saveProblem = "Your paired desktop changed. Open the video again."
            return
        }
        let sent = state
        let body = MakeVideoCodec.body(base: base, filled: live.filled, mine: sent, ids: live.ids)
        live.saving = true
        live.saveProblem = nil
        live.writeSerial += 1
        let result: SaveResult
        do {
            result = .saved(try await liveClient().makeVideoSave(projectID, body: body))
        } catch {
            Connection.shared.note(error)
            if case .server(let status, let detail)? = error as? APIError, status == 409 {
                _ = detail
                result = .changed
            } else if Self.wasRefused(error) {
                result = .refused(Self.serverText(error))
            } else {
                result = .lost
            }
        }
        live.writeSerial += 1
        live.saving = false
        guard stillLive(live) else { return }
        switch result {
        case .saved(let saved):
            adoptSaved(saved, sent: sent, live: live)
            live.notice = nil
            toast?.say("Saved.")
            Haptics.success()
        case .refused(let why):
            live.saveProblem = "Your desktop did not save this. " + why
        case .changed:
            live.pendingSent = nil
            live.notice = "This video changed on your desktop. Your changes are still here, on top of the new version. Check them, then save again."
            live.readSerial += 1
            let before = live.doc?.version
            let read = await loadLive()
            if !read {
                live.saveProblem = "Your desktop could not be read again. Your changes are still here. Try Save again in a moment."
            } else if live.doc?.version == before {
                live.notice = nil
            }
        case .lost:
            live.pendingSent = (sent, base.version)
            await reconcileSave(live: live)
        }
    }

    /// The saved project is what the editor is filled from now. Edits made while the save was on its way stay.
    private func adoptSaved(_ saved: MakeVideoDoc, sent: EditorState, live: MakeVideoLive) {
        // A late answer never moves the remembered version backwards.
        var newest = saved
        if let current = live.doc, current.version > saved.version { newest = current }
        let savedState = MakeVideoCodec.state(newest, ids: live.ids)
        let merged = MakeVideoCodec.rebase(base: sent, theirs: savedState, mine: state)
        state = merged.state
        resetHistory()
        live.doc = newest
        live.filled = savedState
        live.seconds = newest.seconds
        live.pendingSent = nil
        live.unconfirmed = nil
        live.saveProblem = nil
        title = newest.title
        discardDraft()
    }

    /// A save whose answer never arrived: read the desktop and compare it with what was SENT.
    private func reconcileSave(live: MakeVideoLive) async {
        guard let pending = live.pendingSent else { return }
        live.checking = true
        live.readSerial += 1
        defer { live.checking = false }
        let read: MakeVideoDoc
        do {
            read = try await liveClient().makeVideoGet(projectID)
        } catch {
            Connection.shared.note(error)
            guard stillLive(live) else { return }
            live.unconfirmed = "Your desktop did not confirm this save, and it could not be read to check. Your changes are still here. Check again before saving."
            return
        }
        guard stillLive(live) else { return }
        live.unconfirmed = nil
        let desktop = MakeVideoCodec.state(read, ids: live.ids)
        if read.version == pending.version {
            live.pendingSent = nil
            live.saveProblem = "Your desktop did not receive this save. Your changes are still here, and you can save again."
        } else if MakeVideoCodec.matches(sent: pending.state, desktop: desktop) {
            adoptSaved(read, sent: pending.state, live: live)
            live.notice = nil
            toast?.say("Saved. Your desktop confirmed it.")
        } else {
            live.pendingSent = nil
            fill(from: read, live: live, dropEdits: false)
            live.notice = "This video changed on your desktop, and not to what you sent. Your changes are still here, on top of the new version. Check them, then save again."
        }
    }

    /// Read the desktop again after an answer that never arrived.
    func checkLive() async {
        guard let live, live.unconfirmed != nil, !live.checking, stillLive(live) else { return }
        if live.pendingSent != nil {
            await reconcileSave(live: live)
            return
        }
        live.checking = true
        defer { live.checking = false }
        guard let read = try? await liveClient().makeVideoGet(projectID), stillLive(live) else { return }
        let dropEdits = live.restoreFrom.map { read.version > $0 } ?? false
        fill(from: read, live: live, dropEdits: dropEdits)
        live.restoreFrom = nil
        live.unconfirmed = nil
    }

    // MARK: Leaving

    /// Keep unsaved edits for the next time this video is opened.
    func stashDraft() {
        guard let live, live.phase == .ready, !live.abandoned, isDirty else { return }
        MakeVideoDrafts.put(MakeVideoDraft(state: state, filled: live.filled, ids: live.ids, version: live.doc?.version ?? 0), account: live.account, video: projectID)
    }

    func discardDraft() {
        guard let live else { return }
        MakeVideoDrafts.drop(account: live.account, video: projectID)
    }

    /// Leave without saving: the edits are not kept for the next time.
    func abandonEdits() {
        live?.abandoned = true
        discardDraft()
    }

    // MARK: History

    func loadHistory() async throws -> [MakeVideoVersionDTO] {
        try await liveClient().makeVideoHistory(projectID)
    }

    /// Make an older version the newest. The person's unsaved edits are dropped (the confirm says so).
    func restoreLive(_ version: Int) async -> String? {
        guard let live, !live.restoring, !live.saving, live.unconfirmed == nil, stillLive(live), let base = live.doc else {
            return "Not now. Wait for the desktop to finish what it is doing."
        }
        live.restoring = true
        live.writeSerial += 1
        live.restoreFrom = base.version
        defer {
            live.writeSerial += 1
            live.restoring = false
        }
        do {
            let saved = try await liveClient().makeVideoRestore(projectID, version: version)
            guard stillLive(live) else { return nil }
            fill(from: saved, live: live, dropEdits: true)
            live.restoreFrom = nil
            live.notice = nil
            live.saveProblem = nil
            discardDraft()
            toast?.say("Version \(version) is the newest version again.")
            return nil
        } catch {
            Connection.shared.note(error)
            guard stillLive(live) else { return nil }
            if Self.wasRefused(error) {
                live.restoreFrom = nil
                return "Your desktop did not restore it. " + Self.serverText(error)
            }
            // The answer never arrived: read the desktop and show what it really has.
            do {
                let read = try await liveClient().makeVideoGet(projectID)
                guard stillLive(live) else { return nil }
                let moved = read.version > base.version
                fill(from: read, live: live, dropEdits: moved)
                live.restoreFrom = nil
                if moved { discardDraft() }
                return moved ? "Your desktop did not confirm it, but it now holds version \(read.version)."
                             : "Your desktop did not receive it. Nothing changed."
            } catch {
                live.unconfirmed = "Your desktop did not confirm the restore, and it could not be read to check. Check again before changing anything."
                return live.unconfirmed
            }
        }
    }

    // MARK: Comments pinned on the preview

    func refreshReview() async {
        guard let live, stillLive(live) else { return }
        do {
            let read = try await liveClient().makeVideoReview(projectID)
            guard stillLive(live) else { return }
            live.review = read
            live.knownRuns.formUnion(read.runs.map(\.id))
            comments = read.comments.filter(\.open).map {
                EditorComment(id: live.ids.handle("comment", $0.id), time: $0.t, text: $0.text)
            }
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            Connection.shared.note(error)
        }
    }

    // MARK: Render

    /// Render is on while nothing is unsaved, no render of this video is running and the desktop has been asked.
    var canRenderLive: Bool {
        guard let live, live.phase == .ready else { return false }
        return !isDirty && !live.renderBusy && !live.renderUnchecked && !live.stopping && live.job?.isActive != true
            && live.unconfirmed == nil && !live.saving && !live.narrating
    }

    var rendersLive: Bool { live?.job?.isActive == true }

    var showsRenderCard: Bool {
        guard let live else { return render != .idle }
        return live.job != nil || live.renderLine != nil || live.renderBusy || live.renderUnchecked
    }

    /// First step: can the desktop render at all, and is this video already rendering? Then a confirm.
    func prepareRenderLive() async {
        guard let live, canRenderLive, stillLive(live) else { return }
        live.renderBusy = true
        live.renderLine = nil
        defer { live.renderBusy = false }
        do {
            let check = try await liveClient().makeVideoFfmpeg()
            guard stillLive(live) else { return }
            guard check.found else {
                live.renderLine = "Your desktop cannot render yet. " + (check.message.isEmpty ? "FFmpeg was not found." : check.message)
                return
            }
            let resources = try await liveClient().makeVideoResources(projectID)
            guard stillLive(live) else { return }
            live.knownJobs = Set(resources.jobs.map(\.id))
            live.jobsKnown = true
            if let running = resources.jobs.last(where: { $0.videoID == projectID && !$0.isExport && $0.isActive }) {
                live.job = running
                live.renderLine = "This video is already rendering on your desktop."
                watchJob()
                return
            }
            confirm = .render
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            Connection.shared.note(error)
            guard stillLive(live) else { return }
            if case .server(let status, _)? = error as? APIError, status == 409 || status == 404 {
                live.renderLine = "To render from your iPhone, turn on Studio in Tool Store, Tabs, on your desktop. It is how this app sees which renders are running."
            } else {
                live.renderLine = "Your desktop could not be asked about rendering. " + error.plainWords
            }
        }
    }

    /// The confirmed start. One render at a time; an answer that never arrives is settled by reading the jobs.
    func startRenderLive() async {
        guard let live, canRenderLive, stillLive(live) else { return }
        let aspect = live.renderAspect.isEmpty ? (live.doc?.aspects.first ?? "16:9") : live.renderAspect
        live.renderBusy = true
        live.renderLine = nil
        live.writeSerial += 1
        let known = live.knownJobs
        defer {
            live.writeSerial += 1
            live.renderBusy = false
        }
        do {
            let job = try await liveClient().makeVideoRenderStart(projectID, aspect: aspect)
            guard stillLive(live) else { return }
            live.job = job
            live.knownJobs.insert(job.id)
            Haptics.success()
            watchJob()
        } catch {
            Connection.shared.note(error)
            guard stillLive(live) else { return }
            if Self.wasRefused(error) {
                live.renderLine = "Your desktop did not start the render. " + Self.serverText(error)
                return
            }
            await settleRender(live: live, aspect: aspect, known: known, because: error.plainWords)
        }
    }

    /// The start's answer never arrived: look at the desktop's jobs for one that was not there before.
    private func settleRender(live: MakeVideoLive, aspect: String, known: Set<String>, because: String) async {
        do {
            let resources = try await liveClient().makeVideoResources(projectID)
            guard stillLive(live) else { return }
            live.renderUnchecked = false
            live.knownJobs = Set(resources.jobs.map(\.id))
            if let started = resources.jobs.last(where: {
                $0.videoID == projectID && !$0.isExport && $0.aspect == aspect && !known.contains($0.id)
            }) {
                live.job = started
                live.renderLine = "Your desktop did not confirm the start, but a render is running there."
                if started.isActive { watchJob() }
            } else {
                live.renderLine = "Your desktop did not confirm the start, and it shows no new render, so none was started. You can try again."
            }
        } catch {
            guard stillLive(live) else { return }
            live.renderUnchecked = true
            live.renderLine = "Your desktop did not confirm the start, and it could not be read to check. Render stays off until it can be. " + because
        }
    }

    /// Read the jobs again after a start that could not be settled.
    func checkRenderLive() async {
        guard let live, live.renderUnchecked, !live.renderBusy, stillLive(live) else { return }
        live.renderBusy = true
        defer { live.renderBusy = false }
        let aspect = live.renderAspect.isEmpty ? (live.doc?.aspects.first ?? "16:9") : live.renderAspect
        await settleRender(live: live, aspect: aspect, known: live.knownJobs, because: "")
    }

    /// A render already running for this video (started here earlier or on the desktop) is shown, not started again.
    func adoptRunningJob() async {
        guard let live, stillLive(live) else { return }
        guard let resources = try? await liveClient().makeVideoResources(projectID), stillLive(live) else { return }
        live.jobsKnown = true
        live.knownJobs = Set(resources.jobs.map(\.id))
        if live.job == nil, let running = resources.jobs.last(where: { $0.videoID == projectID && !$0.isExport && $0.isActive }) {
            live.job = running
            watchJob()
        }
    }

    /// Follow the desktop's own job until it ends. Progress comes from what the desktop says, never from a timer.
    func watchJob() {
        guard let live, let job = live.job, job.isActive else { return }
        live.watchTask?.cancel()
        let jobID = job.id
        live.watchTask = Task { [weak self, weak live] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, let live, self.stillLive(live), live.job?.id == jobID else { return }
                do {
                    let next = try await self.liveClient().makeVideoJob(jobID)
                    guard self.stillLive(live), live.job?.id == jobID else { return }
                    live.job = next
                    live.renderLine = nil
                    if !next.isActive {
                        if next.isReady {
                            Haptics.success()
                            self.toast?.say("Rendered on your desktop.")
                        }
                        return
                    }
                } catch {
                    if error is CancellationError || Task.isCancelled { return }
                    Connection.shared.note(error)
                    guard self.stillLive(live), live.job?.id == jobID else { return }
                    if case .server(let status, _)? = error as? APIError, status == 404 {
                        live.job = nil
                        live.renderLine = "Your desktop no longer has this render. It may have restarted."
                        return
                    }
                    live.renderLine = "Waiting for your desktop to answer. " + error.plainWords
                }
            }
        }
    }

    func stopWatching() {
        live?.watchTask?.cancel()
        live?.askWatchTask?.cancel()
    }

    func stopRenderLive() async {
        guard let live, let job = live.job, job.isActive, !live.stopping, stillLive(live) else { return }
        live.stopping = true
        defer { live.stopping = false }
        do {
            let next = try await liveClient().makeVideoJobCancel(job.id)
            guard stillLive(live), live.job?.id == job.id else { return }
            live.job = next
            live.renderLine = nil
        } catch {
            Connection.shared.note(error)
            guard stillLive(live) else { return }
            if Self.wasRefused(error) {
                live.renderLine = "Your desktop did not stop it. " + Self.serverText(error)
                return
            }
            // The answer never arrived: read the job and show what it really says.
            if let read = try? await liveClient().makeVideoJob(job.id), stillLive(live), live.job?.id == job.id {
                live.job = read
                live.renderLine = read.isActive ? "Your desktop did not confirm the stop, and the render is still going." : nil
                if read.isActive { watchJob() }
            } else {
                live.renderLine = "Your desktop did not confirm the stop, and it could not be read to check. The render may still be going."
            }
        }
    }

    func dismissRender() {
        guard let live, live.job?.isActive != true else { return }
        live.job = nil
        live.renderLine = nil
    }

    // MARK: Narration

    var canNarrateLive: Bool {
        guard let live, live.phase == .ready, let doc = live.doc else { return false }
        return doc.unspokenLines > 0 && !isDirty && !live.narrating && !live.saving && live.unconfirmed == nil
            && live.job?.isActive != true && !live.narrateUnconfirmed && !live.narrateChecking
    }

    /// Read the video again after a narrate answer that never arrived. Narrate comes back on only when a line
    /// shows as spoken.
    func checkNarrateLive() async {
        guard let live, live.narrateUnconfirmed, !live.narrateChecking, !live.narrating, stillLive(live) else { return }
        live.narrateChecking = true
        defer { live.narrateChecking = false }
        do {
            let read = try await liveClient().makeVideoGet(projectID)
            guard stillLive(live) else { return }
            fill(from: read, live: live, dropEdits: false)
            if read.unspokenLines < live.narrateMissing {
                live.narrationLine = "Your desktop did not confirm it, but \(live.narrateMissing - read.unspokenLines) of the lines are spoken now."
            } else {
                live.narrationLine = "No new line is spoken yet. Your desktop may still be working, so Narrate stays off. Check again in a minute."
            }
        } catch {
            guard stillLive(live) else { return }
            live.narrationLine = "Your desktop could not be read to check. Narrate stays off. Try again in a moment."
        }
    }

    /// Speak the lines not spoken yet. One at a time; an answer that never arrives is settled by reading the video.
    func narrateLive() async {
        guard let live, canNarrateLive, stillLive(live), let base = live.doc else { return }
        live.narrating = true
        live.narrationLine = nil
        live.writeSerial += 1
        let missing = base.unspokenLines
        defer {
            live.writeSerial += 1
            live.narrating = false
        }
        do {
            let saved = try await liveClient().makeVideoNarrate(projectID)
            guard stillLive(live) else { return }
            fill(from: saved, live: live, dropEdits: false)
            live.narrationLine = saved.unspokenLines == 0 ? "Every line is spoken now." : "\(saved.unspokenLines) lines are still not spoken."
            Haptics.success()
        } catch {
            Connection.shared.note(error)
            guard stillLive(live) else { return }
            if Self.wasRefused(error) || Self.statusOf(error) == 503 {
                live.narrationLine = "Your desktop did not speak the lines. " + Self.serverText(error)
                return
            }
            // Narrate stays off until the desktop shows a spoken line.
            live.narrateMissing = missing
            live.narrateUnconfirmed = true
            do {
                let read = try await liveClient().makeVideoGet(projectID)
                guard stillLive(live) else { return }
                fill(from: read, live: live, dropEdits: false)
                if read.unspokenLines < missing {
                    live.narrationLine = "Your desktop did not confirm it, but \(missing - read.unspokenLines) of the lines are spoken now."
                } else {
                    live.narrationLine = "Your desktop did not confirm it, and no new line is spoken yet. It may still be working, so Narrate stays off. Check again in a minute."
                }
            } catch {
                live.narrationLine = "Your desktop did not confirm it, and it could not be read to check. Narrate stays off until it can be."
            }
        }
    }

    // MARK: Ask Kairos

    /// Ask is on while nothing is unsaved: Kairos works on the version saved on the desktop.
    var canAskLive: Bool {
        guard let live else { return false }
        return askReady && !live.askUnconfirmed
    }

    private var askReady: Bool {
        guard let live, live.phase == .ready else { return false }
        return !isDirty && !live.askBusy && !live.askChecking && live.unconfirmed == nil && !live.saving
    }

    /// After 15 minutes with no new run on the desktop, the person may ask again, only through a confirm.
    var canAskAgain: Bool {
        guard let live else { return false }
        return askReady && live.askUnconfirmed && live.askMayRepeat
    }

    static let askRepeatAfter: TimeInterval = 15 * 60
    static let askRepeatDetail = "Your first request may still be running on your desktop, and it may be charged twice. Ask again only if you are sure it is not."

    /// One model turn on the desktop. No request id exists, so it is sent once. After a lost answer the runs are
    /// read about every 15 seconds, and it is sent again only after 15 minutes with no new run and a confirm (`again`).
    func askLive(_ text: String, includeComments: Bool, again: Bool = false) async {
        guard let live, again ? canAskAgain : canAskLive, stillLive(live) else { return }
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let openComments = includeComments ? (live.review?.comments.filter(\.open).map(\.id) ?? []) : []
        guard !request.isEmpty || !openComments.isEmpty else { return }
        var selected: [String: Any] = ["time": MakeVideoWire.round4(playhead)]
        switch selection {
        case .beat(let id)?: if let did = live.ids.desktopID(id) { selected["beats"] = [did] }
        case .clip(let id)?: if let did = live.ids.desktopID(id) { selected["clips"] = [did] }
        case nil: break
        }
        if let range = workRange { selected["region"] = ["start": MakeVideoWire.round4(range.lowerBound), "end": MakeVideoWire.round4(range.upperBound)] }
        live.askBusy = true
        live.askLine = nil
        live.writeSerial += 1
        let before = live.knownRuns
        let sentAt = Date()
        if again {
            live.clearAsk()
            live.askWatchTask?.cancel()
        }
        defer {
            live.writeSerial += 1
            live.askBusy = false
        }
        do {
            let run = try await liveClient().makeVideoAsk(projectID, request: request, selection: selected, comments: openComments)
            guard stillLive(live) else { return }
            live.latestRun = run
            live.knownRuns.insert(run.id)
            await afterRun(live: live)
        } catch {
            Connection.shared.note(error)
            guard stillLive(live) else { return }
            if Self.wasRefused(error) {
                live.askLine = "Kairos could not do that. " + Self.serverText(error)
                return
            }
            live.askUnconfirmed = true
            live.askMayRepeat = false
            live.askSince = sentAt
            live.askBefore = before
            live.askRequest = request
            MakeVideoAskStore.put(MakeVideoAskPending(since: sentAt, before: before, request: request), account: live.account, video: projectID)
            await settleAsk(live: live)
            watchAsk()
        }
    }

    /// While the answer is unconfirmed and the editor is showing, read the runs about every 15 seconds.
    func watchAsk() {
        guard let live, live.askUnconfirmed else { return }
        live.askWatchTask?.cancel()
        live.askWatchTask = Task { [weak self, weak live] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, let live, self.stillLive(live), live.askUnconfirmed else { return }
                await self.checkAskLive(quiet: true)
            }
        }
    }

    /// The run that is this Ask's: not there before it was sent, and with the same stripped request text.
    private static func askRun(in runs: [MakeVideoRunDTO], live: MakeVideoLive) -> MakeVideoRunDTO? {
        runs.first { run in
            !live.askBefore.contains(run.id)
                && run.request.trimmingCharacters(in: .whitespacesAndNewlines) == live.askRequest
        }
    }

    /// The answer never arrived: read the runs for one that was not there before.
    private func settleAsk(live: MakeVideoLive) async {
        do {
            let read = try await liveClient().makeVideoReview(projectID)
            guard stillLive(live) else { return }
            live.review = read
            live.knownRuns.formUnion(read.runs.map(\.id))
            if let fresh = Self.askRun(in: read.runs, live: live) {
                live.latestRun = fresh
                live.clearAsk()
                live.askLine = "Your desktop did not confirm the answer, but Kairos did reply there."
                await afterRun(live: live)
            } else {
                live.askLine = "Your desktop did not confirm the answer, and no new reply is there yet. Kairos may still be working. Ask stays off, and this screen keeps checking."
            }
        } catch {
            guard stillLive(live) else { return }
            live.askLine = "Your desktop did not confirm the answer, and it could not be read to check. Ask stays off, and this screen keeps trying."
        }
    }

    /// Read the desktop again after Kairos may have changed the video. Finding nothing new never turns Ask back on:
    /// only a new run does, or 15 minutes without one (then a confirm is needed to ask again).
    func checkAskLive(quiet: Bool = false) async {
        guard let live, live.askUnconfirmed, !live.askBusy, !live.askChecking, stillLive(live) else { return }
        live.askChecking = true
        defer { live.askChecking = false }
        do {
            let read = try await liveClient().makeVideoReview(projectID)
            guard stillLive(live), live.askUnconfirmed else { return }
            live.review = read
            if let fresh = Self.askRun(in: read.runs, live: live) {
                live.knownRuns.formUnion(read.runs.map(\.id))
                live.latestRun = fresh
                live.clearAsk()
                live.askLine = "Kairos did reply on your desktop."
                await afterRun(live: live)
            } else if let since = live.askSince, Date().timeIntervalSince(since) >= Self.askRepeatAfter {
                live.askMayRepeat = true
                live.askLine = "Nothing new has shown up on your desktop in 15 minutes. You can ask again, but the first request may still be running there."
            } else {
                live.askLine = "Nothing new has shown up on your desktop yet. Kairos may still be working. Ask stays off until it does."
            }
        } catch {
            guard stillLive(live) else { return }
            if !quiet { live.askLine = "Your desktop could not be read to check. Try again in a moment." }
        }
    }

    func runActionLive(_ run: MakeVideoRunDTO, action: MakeVideoRunAction) async {
        guard let live, !live.askBusy, stillLive(live) else { return }
        live.askBusy = true
        live.askLine = nil
        live.writeSerial += 1
        defer {
            live.writeSerial += 1
            live.askBusy = false
        }
        do {
            let result = try await liveClient().makeVideoRunAction(projectID, run: run.id, action: action)
            guard stillLive(live) else { return }
            live.latestRun = result
            await afterRun(live: live)
        } catch {
            Connection.shared.note(error)
            guard stillLive(live) else { return }
            if Self.wasRefused(error) {
                live.askLine = "Your desktop did not do that. " + Self.serverText(error)
                await afterRun(live: live)
                return
            }
            // The answer never arrived: read the runs and the video and show what they say. Never sent again from here.
            await afterRun(live: live)
            if let now = live.review?.runs.first(where: { $0.id == run.id }) {
                live.latestRun = now
                live.askLine = "Your desktop did not confirm it. It now shows this change as \(now.status)."
            } else {
                live.askLine = "Your desktop did not confirm it, and the change could not be read to check."
            }
        }
    }

    /// The video and the runs may have changed on the desktop: read both. The person's edits stay.
    private func afterRun(live: MakeVideoLive) async {
        live.readSerial += 1
        if let read = try? await liveClient().makeVideoGet(projectID), stillLive(live), !live.saving {
            fill(from: read, live: live, dropEdits: false)
        }
        await refreshReview()
    }
}

// MARK: - Views for the paired desktop

/// What stands in for the editor while the video is read, is not on the desktop, or could not be read.
struct EditorLiveNote: View {
    let model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.live?.phase ?? .loading {
            case .loading, .ready:
                HStack(spacing: 10) {
                    PulsingDot(color: Palette.working)
                    Text("Reading your video from your desktop.")
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                }
            case .missing:
                EmptyLine(text: "Pick a video from the list in Make.")
            case .failed(let text):
                EmptyLine(text: text)
                MakePillButton(title: "Try again", symbol: "arrow.clockwise") { Task { await model.loadLive() } }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 20)
    }
}

/// Save, and what the desktop last said about it.
struct EditorLiveBar: View {
    let model: EditorModel

    var body: some View {
        if let live = model.live {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline(live))
                            .font(KFont.ui(15.5, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Palette.ink)
                        if let version = live.doc?.version {
                            Text("Version \(version) on your desktop")
                                .font(KFont.ui(12.5, relativeTo: .caption))
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                    Spacer(minLength: 6)
                    if live.unconfirmed != nil {
                        MakePillButton(title: live.checking ? "Checking" : "Check", symbol: "arrow.clockwise", filled: true) {
                            Task { await model.checkLive() }
                        }
                        .editorEnabled(!live.checking)
                    } else {
                        MakePillButton(title: live.saving ? "Saving" : "Save", symbol: "checkmark", filled: true) {
                            Task { await model.saveLive() }
                        }
                        .editorEnabled(model.canSaveLive)
                    }
                }
                if let text = live.unconfirmed ?? live.saveProblem ?? live.notice {
                    HintLine(text: text, symbol: "info.circle", color: live.unconfirmed != nil || live.saveProblem != nil ? Palette.goldText : Palette.inkDim)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 18)
        }
    }

    private func headline(_ live: MakeVideoLive) -> String {
        if live.saving { return "Saving to your desktop" }
        if live.unconfirmed != nil { return "Not confirmed" }
        return model.isDirty ? "You have unsaved changes" : "Everything is saved"
    }
}

/// History and narration, under the Ask and Render buttons.
struct EditorLiveTools: View {
    let model: EditorModel

    var body: some View {
        if let live = model.live {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    MakePillButton(title: "History", symbol: "clock.arrow.circlepath", expand: true) { model.sheet = .history }
                        .editorEnabled(!live.saving && !live.restoring)
                    if let doc = live.doc, doc.unspokenLines > 0 {
                        MakePillButton(title: live.narrating ? "Speaking" : "Narrate", symbol: "waveform", expand: true) {
                            model.confirm = .narrate
                        }
                        .editorEnabled(model.canNarrateLive)
                    }
                }
                if let doc = live.doc, doc.unspokenLines > 0, !live.narrating {
                    HintLine(text: "\(doc.unspokenLines) \(doc.unspokenLines == 1 ? "line is" : "lines are") not spoken yet. A render speaks them first.",
                             symbol: "waveform")
                }
                if live.narrating {
                    HintLine(text: "Your desktop is speaking the lines. It can take a few minutes, and it must stay open.", symbol: "hourglass")
                }
                if let text = live.narrationLine {
                    HintLine(text: text, symbol: "info.circle")
                }
                if live.narrateUnconfirmed {
                    MakePillButton(title: live.narrateChecking ? "Checking" : "Check again", symbol: "arrow.clockwise") {
                        Task { await model.checkNarrateLive() }
                    }
                    .editorEnabled(!live.narrateChecking && !live.narrating)
                }
                if model.isDirty {
                    HintLine(text: "Save your changes to render, ask Kairos or narrate. They work on the saved version.", symbol: "arrow.down.doc")
                }
                if live.doc?.isChaptered == true {
                    HintLine(text: "A long video's plan is approved in Studio, in Make.", symbol: "checklist")
                }
            }
        }
    }
}

/// A render of this video on the desktop, from the desktop's own job.
struct EditorLiveRenderCard: View {
    let model: EditorModel
    @State private var showStop = false

    var body: some View {
        if let live = model.live {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Render")
                        .font(KFont.ui(16, .semibold, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    pill(live)
                }
                if let aspects = live.doc?.aspects, aspects.count > 1, live.job?.isActive != true {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(aspects, id: \.self) { aspect in
                                Button {
                                    Haptics.select()
                                    live.renderAspect = aspect
                                } label: {
                                    Chip(text: aspect, filled: live.renderAspect == aspect)
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                if let job = live.job {
                    if job.isActive {
                        bar(job.progress)
                        HStack(spacing: 10) {
                            Text(job.words)
                                .font(KFont.ui(14.5, relativeTo: .subheadline))
                                .foregroundStyle(Palette.inkDim)
                                .contentTransition(.numericText())
                            Spacer()
                            MakePillButton(title: live.stopping ? "Stopping" : "Stop", symbol: "stop.fill") { showStop = true }
                                .editorEnabled(!live.stopping)
                        }
                        Text("Your desktop is rendering. It must stay open until it finishes.")
                            .font(KFont.ui(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                    } else if job.isReady {
                        Text(readyLine(job))
                            .font(KFont.ui(15, relativeTo: .subheadline))
                            .foregroundStyle(Palette.ink)
                        if let file = job.file {
                            Text(file)
                                .font(KFont.ui(13.5, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        ForEach(Array(job.notes.prefix(4).enumerated()), id: \.offset) { _, note in
                            HintLine(text: note, symbol: "exclamationmark.circle")
                        }
                        MakePillButton(title: "Close", expand: true) { model.dismissRender() }
                    } else {
                        Text(job.words)
                            .font(KFont.ui(14.5, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                        MakePillButton(title: "Close", expand: true) { model.dismissRender() }
                    }
                }
                if let line = live.renderLine {
                    HintLine(text: line, symbol: "info.circle")
                }
                if live.renderUnchecked {
                    MakePillButton(title: live.renderBusy ? "Checking" : "Check again", symbol: "arrow.clockwise") {
                        Task { await model.checkRenderLive() }
                    }
                    .editorEnabled(!live.renderBusy)
                }
                if live.job == nil, live.renderBusy {
                    HStack(spacing: 10) {
                        PulsingDot(color: Palette.working)
                        Text("Asking your desktop.")
                            .font(KFont.ui(14.5, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkDim)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 20)
            .sheet(isPresented: $showStop) {
                ConfirmSheet(title: "Stop this render?", detail: "Your desktop stops drawing this video. A short video starts again from the beginning next time.",
                             confirm: "Stop render") {
                    Task { await model.stopRenderLive() }
                }
            }
        }
    }

    private func readyLine(_ job: MakeVideoJobDTO) -> String {
        guard let seconds = job.seconds else { return "Rendered on your desktop." }
        return "Rendered on your desktop, " + EditorFormat.clock(seconds) + "."
    }

    @ViewBuilder private func pill(_ live: MakeVideoLive) -> some View {
        if let job = live.job {
            if job.isActive {
                StatePill(text: "Rendering", tone: .working)
            } else if job.isReady {
                StatePill(text: "Ready", tone: .ok)
            } else if job.isFailed {
                StatePill(text: "Stopped", tone: .warn)
            } else {
                StatePill(text: "Paused", tone: .warn)
            }
        }
    }

    private func bar(_ progress: Double?) -> some View {
        Capsule()
            .fill(Palette.ink.opacity(0.1))
            .frame(height: 8)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(Palette.gold).frame(width: geo.size.width * CGFloat(progress ?? 0.04))
                }
            }
            .animation(Motion.gentle, value: progress)
            .accessibilityElement()
            .accessibilityLabel("Render progress")
            .accessibilityValue(progress.map { "\(Int(($0 * 100).rounded()))%" } ?? "Starting")
    }
}

/// The video's saved versions, newest first, and a way back to any of them.
struct EditorHistorySheet: View {
    let model: EditorModel
    @State private var versions: [MakeVideoVersionDTO] = []
    @State private var loading = true
    @State private var problem: String?
    @State private var pick: MakeVideoVersionDTO?
    @State private var result: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MakeSheetTitle(title: "History", detail: "Your desktop keeps the last 30 saved versions.")
                if let result { HintLine(text: result, symbol: "info.circle") }
                if loading {
                    HStack(spacing: 10) {
                        PulsingDot(color: Palette.working)
                        Text("Reading the versions.").font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
                    }
                } else if let problem {
                    EmptyLine(text: problem)
                    MakePillButton(title: "Try again", symbol: "arrow.clockwise") { Task { await load() } }
                } else if versions.isEmpty {
                    EmptyLine(text: "No saved versions yet.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(versions.enumerated()), id: \.element.version) { index, version in
                            row(version, last: index == versions.count - 1)
                        }
                    }
                    .kCard(radius: 20)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .kSheet([.medium, .large])
        .interactiveDismissDisabled(model.live?.restoring == true)
        .task { await load() }
        .sheet(item: $pick) { version in
            ConfirmSheet(title: "Go back to version \(version.version)?",
                         detail: restoreDetail,
                         confirm: "Restore version \(version.version)", danger: false) {
                Task {
                    result = await model.restoreLive(version.version)
                    await load()
                }
            }
        }
    }

    private var restoreDetail: String {
        var text = "Your desktop makes this version the newest one. The versions after it stay in the history."
        if model.isDirty { text += " Your unsaved changes here are lost." }
        return text
    }

    private func row(_ version: MakeVideoVersionDTO, last: Bool) -> some View {
        let current = version.version == model.live?.doc?.version
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Version \(version.version)")
                    .font(KFont.ui(16, .medium, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                Text(detail(version))
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if current {
                StatePill(text: "Newest", tone: .ok)
            } else {
                MakePillButton(title: "Restore") { pick = version }
                    .editorEnabled(model.live?.restoring != true && model.live?.unconfirmed == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 16) }
        }
    }

    private func detail(_ version: MakeVideoVersionDTO) -> String {
        var parts: [String] = []
        if let updated = version.updated { parts.append(updated.formatted(date: .abbreviated, time: .shortened)) }
        parts.append("\(version.beats) \(version.beats == 1 ? "beat" : "beats")")
        parts.append(EditorFormat.clock(version.seconds))
        return parts.joined(separator: ", ")
    }

    private func load() async {
        loading = true
        problem = nil
        do {
            let read = try await model.loadHistory()
            versions = read
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            Connection.shared.note(error)
            problem = "The versions could not be read. " + error.plainWords
        }
        loading = false
    }
}

/// Ask Kairos on the paired desktop: one request at a time, and what Kairos did, with Apply, Discard and Undo.
struct EditorLiveAskSheet: View {
    let model: EditorModel
    @State private var text = ""
    @State private var includeComments = false
    @State private var undoRun: MakeVideoRunDTO?
    @State private var askAgain = false

    private let ideas = ["Make the opening shorter", "Warmer caption for this beat", "Punchier last line", "Say the sale ends Friday"]

    var body: some View {
        let live = model.live
        FittedSheet(estimate: 520) {
            VStack(alignment: .leading, spacing: 16) {
                MakeSheetTitle(title: "Ask Kairos", detail: "Kairos changes the video saved on your desktop. Undo takes a change back.")
                if model.isDirty {
                    HintLine(text: "Save your changes first. Kairos works on the saved version.", symbol: "arrow.down.doc")
                }
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
                let open = live?.review?.comments.filter(\.open).count ?? 0
                if open > 0 {
                    EditorGroup {
                        MakeToggleRow(title: "Also answer \(open) open \(open == 1 ? "comment" : "comments")", isOn: $includeComments, last: true)
                    }
                }
                if live?.askBusy == true {
                    HStack(spacing: 10) {
                        PulsingDot(color: Palette.working)
                        Text("Kairos is working on your desktop.")
                            .font(KFont.ui(14.5, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkDim)
                    }
                }
                GoldButton(title: live?.askBusy == true ? "Working" : "Send") {
                    Haptics.tap()
                    let request = text
                    Task { await model.askLive(request, includeComments: includeComments) }
                }
                .editorEnabled(model.canAskLive && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || includeComments))
                Text("This runs a model turn on your desktop, which may use paid credit. Each request is sent once.")
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                if let line = live?.askLine { HintLine(text: line, symbol: "info.circle") }
                if live?.askUnconfirmed == true {
                    MakePillButton(title: live?.askChecking == true ? "Checking" : "Check again", symbol: "arrow.clockwise") {
                        Task { await model.checkAskLive() }
                    }
                    .editorEnabled(live?.askBusy != true && live?.askChecking != true)
                    if live?.askMayRepeat == true {
                        MakePillButton(title: "Ask again anyway", symbol: "exclamationmark.triangle") { askAgain = true }
                            .editorEnabled(model.canAskAgain && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || includeComments))
                    }
                }
                if let run = live?.latestRun ?? live?.review?.runs.first {
                    runCard(run)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .interactiveDismissDisabled(live?.askBusy == true)
        .sheet(isPresented: $askAgain) {
            ConfirmSheet(title: "Ask again?", detail: EditorModel.askRepeatDetail, confirm: "Ask again") {
                let request = text
                Task { await model.askLive(request, includeComments: includeComments, again: true) }
            }
        }
        .sheet(item: $undoRun) { run in
            ConfirmSheet(title: "Undo this change?",
                         detail: "Your desktop takes back what Kairos changed in this run, unless you changed it again since.",
                         confirm: "Undo change") {
                Task { await model.runActionLive(run, action: .undo) }
            }
        }
    }

    @ViewBuilder private func runCard(_ run: MakeVideoRunDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kairos").font(KFont.ui(15.5, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                Spacer()
                StatePill(text: statusWord(run), tone: tone(run))
            }
            if !run.reply.isEmpty {
                Text(run.reply)
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = run.error, !error.isEmpty {
                HintLine(text: error, symbol: "exclamationmark.circle", color: Palette.goldText)
            }
            ForEach(Array(run.changes.prefix(8).enumerated()), id: \.offset) { _, change in
                HintLine(text: change.words, symbol: "circle.fill")
            }
            if run.changes.count > 8 {
                HintLine(text: "And \(run.changes.count - 8) more.")
            }
            if run.isPending {
                HintLine(text: "Kairos held this for your OK because it changes a lot. Nothing has changed yet.", symbol: "hand.raised")
                HStack(spacing: 8) {
                    MakePillButton(title: "Discard", expand: true) { Task { await model.runActionLive(run, action: .discard) } }
                    MakePillButton(title: "Apply", filled: true, expand: true) { Task { await model.runActionLive(run, action: .apply) } }
                }
                .editorEnabled(model.live?.askBusy != true)
            } else if run.isApplied {
                MakePillButton(title: "Undo Kairos's change", symbol: "arrow.uturn.backward", expand: true) { undoRun = run }
                    .editorEnabled(model.live?.askBusy != true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 18)
    }

    private func statusWord(_ run: MakeVideoRunDTO) -> String {
        switch run.status {
        case "applied": return "Applied"
        case "pending": return "Waiting for you"
        case "discarded": return "Discarded"
        case "undone": return "Undone"
        case "failed": return "Not done"
        default: return "Answered"
        }
    }

    private func tone(_ run: MakeVideoRunDTO) -> PillTone {
        switch run.status {
        case "applied": return .ok
        case "pending": return .gold
        case "failed": return .warn
        default: return .muted
        }
    }
}
