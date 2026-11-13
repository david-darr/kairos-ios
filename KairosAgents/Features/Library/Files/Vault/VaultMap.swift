import SwiftUI

// The Map: folders as circles, notes as triangles, links as lines.
// Drag to pan, pinch to zoom, drag a node to move it, tap a node to peek.

nonisolated struct VaultMapNode: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case folder, note }
    let id: String
    let kind: Kind
    let ref: String
    let title: String
    let group: String
    let weight: Int
    let seed: Double
}

nonisolated struct VaultMapEdge: Hashable, Sendable {
    let from: String
    let to: String
    let spoke: Bool
}

nonisolated enum VaultMapLayout {
    /// Above this many nodes the pairwise force layout costs too much, so the map uses `clusters`.
    static let forceLimit = 400

    /// The whole-vault layout. Small vaults get the force layout; large ones the grouped rings,
    /// which are linear in the number of nodes. Deterministic for the same input. Never call it on the main actor.
    static func compute(nodes: [VaultMapNode], edges: [VaultMapEdge], iterations: Int = 260) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        if nodes.count > forceLimit { return clusters(nodes: nodes) }
        return force(nodes: nodes, edges: edges, iterations: iterations)
    }

    /// A small force layout: nodes push apart, edges pull together.
    static func force(nodes: [VaultMapNode], edges: [VaultMapEdge], iterations: Int) -> [String: CGPoint] {
        let count = nodes.count
        var index: [String: Int] = [:]
        index.reserveCapacity(count)
        var xs = [Double](repeating: 0, count: count)
        var ys = [Double](repeating: 0, count: count)
        for (i, node) in nodes.enumerated() {
            index[node.id] = i
            let angle = Double(i) * 2.399963
            let radius = 30 + 14 * sqrt(Double(i))
            xs[i] = radius * cos(angle)
            ys[i] = radius * sin(angle)
        }
        let links: [(a: Int, b: Int, rest: Double, strength: Double)] = edges.compactMap { edge in
            guard let a = index[edge.from], let b = index[edge.to] else { return nil }
            return (a, b, edge.spoke ? 70 : 90, edge.spoke ? 0.03 : 0.05)
        }
        var fxs = [Double](repeating: 0, count: count)
        var fys = [Double](repeating: 0, count: count)
        for step in 0..<iterations {
            let cooling = 1 - Double(step) / Double(iterations)
            for i in 0..<count { fxs[i] = 0; fys[i] = 0 }
            for i in 0..<count {
                for j in (i + 1)..<count {
                    var dx = xs[i] - xs[j], dy = ys[i] - ys[j]
                    var distance = sqrt(dx * dx + dy * dy)
                    if distance < 0.5 { dx = 0.5; dy = 0.3; distance = 0.6 }
                    let push = 2400 / (distance * distance)
                    let fx = dx / distance * push, fy = dy / distance * push
                    fxs[i] += fx; fys[i] += fy
                    fxs[j] -= fx; fys[j] -= fy
                }
            }
            for link in links {
                let dx = xs[link.b] - xs[link.a], dy = ys[link.b] - ys[link.a]
                let distance = max(1, sqrt(dx * dx + dy * dy))
                let pull = (distance - link.rest) * link.strength
                let fx = dx / distance * pull, fy = dy / distance * pull
                fxs[link.a] += fx; fys[link.a] += fy
                fxs[link.b] -= fx; fys[link.b] -= fy
            }
            let limit = 12 * cooling + 0.5
            for i in 0..<count {
                let fx = fxs[i] - xs[i] * 0.01, fy = fys[i] - ys[i] * 0.01
                let length = sqrt(fx * fx + fy * fy)
                let scale = length > limit ? limit / length : 1
                xs[i] += fx * scale
                ys[i] += fy * scale
            }
        }
        var points: [String: CGPoint] = [:]
        points.reserveCapacity(count)
        for (i, node) in nodes.enumerated() { points[node.id] = CGPoint(x: xs[i], y: ys[i]) }
        return points
    }

    /// A large vault: each group (the one the map colours by) is a disc on a ring around the centre,
    /// sized by its number of nodes, with its nodes in a tight spiral inside it. No pairwise pass.
    static func clusters(nodes: [VaultMapNode]) -> [String: CGPoint] {
        let spacing = 11.0
        let gap = 40.0
        var members: [String: [Int]] = [:]
        for (i, node) in nodes.enumerated() { members[node.group, default: []].append(i) }
        // Biggest groups first, then by name, so the same vault always lands the same way.
        let order = members.keys.sorted { a, b in
            let x = members[a]!.count, y = members[b]!.count
            return x == y ? a < b : x > y
        }
        let radii = order.map { spacing * sqrt(Double(members[$0]!.count)) + 10 }
        var centres: [CGPoint] = []
        if order.count == 1 {
            centres = [.zero]
        } else {
            let around = radii.reduce(0) { $0 + 2 * $1 + gap }
            let ring = max(around / (2 * .pi), (radii.max() ?? 0) + gap)
            var angle = 0.0
            for radius in radii {
                let share = (2 * radius + gap) / around * 2 * .pi
                let middle = angle + share / 2
                centres.append(CGPoint(x: ring * cos(middle), y: ring * sin(middle)))
                angle += share
            }
        }
        var points: [String: CGPoint] = [:]
        points.reserveCapacity(nodes.count)
        for (g, group) in order.enumerated() {
            let centre = centres[g]
            // Input order puts folders first, so they sit in the middle of their group.
            for (k, i) in members[group]!.enumerated() {
                let radius = spacing * sqrt(Double(k) + 0.5)
                let angle = Double(k) * 2.399963
                points[nodes[i].id] = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
            }
        }
        return points
    }

    /// Focus layout: the note in the middle, each step of neighbours on its own ring.
    static func rings(center: String, steps: [String: Int]) -> [String: CGPoint] {
        var result: [String: CGPoint] = [center: .zero]
        let maxStep = steps.values.max() ?? 0
        guard maxStep > 0 else { return result }
        for step in 1...maxStep {
            let ring = steps.filter { $0.value == step }.map(\.key).sorted()
            for (index, id) in ring.enumerated() {
                let angle = Double(index) / Double(max(1, ring.count)) * 2 * .pi + Double(step) * 0.4
                let radius = 120.0 * Double(step)
                result[id] = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            }
        }
        return result
    }
}

/// The vault as a graph, worked out once. Reading every note's links is slow, and the map draws
/// thirty times a second, so nothing here may be worked out while drawing.
struct VaultMapGraph {
    var nodes: [VaultMapNode] = []
    var edges: [VaultMapEdge] = []
    var groups: [String] = []
    var orphans: Set<String> = []
}

struct VaultMapView: View {
    let focus: String?
    @Environment(VaultNav.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = VaultStore.shared

    @State private var graph = VaultMapGraph()
    @State private var layout: [String: CGPoint] = [:]
    @State private var scale: CGFloat = 0.9
    @State private var baseScale: CGFloat = 0.9
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var dragging: String?
    @State private var panning = false
    @State private var selected: String?
    @State private var peek: VaultMapNode?
    @State private var started = Date.now
    @State private var query = ""
    @State private var orphansOnly = false
    @State private var hideFolders = false
    @State private var hideDaily = false
    @State private var project: String?
    @State private var focusID: String?
    @State private var focusDepth = 1
    @State private var viewSize: CGSize = .zero
    @State private var didStart = false
    /// Counts layout runs, so a layout that finishes after the notes changed is thrown away.
    @State private var layoutRun = 0
    @State private var laying = false
    /// Waiting for the layout: centre on the opened note, or fit the whole vault, once it lands.
    @State private var centerWhenLaid: String?
    @State private var fitWhenLaid = false

    private static let tints: [UInt32] = [Palette.botGold, Palette.botPowder, Palette.botSage, Palette.botRose, Palette.botLilac, Palette.botSand, 0x9FB8A0, 0xC9A27A, 0x8FA6C9, 0xD4B483]

    // MARK: Graph data

    private var allNodes: [VaultMapNode] { graph.nodes }
    private var allEdges: [VaultMapEdge] { graph.edges }
    private var groups: [String] { graph.groups }

    private func buildGraph() -> VaultMapGraph {
        let nodes = buildNodes()
        var seen: [String] = []
        var known: Set<String> = []
        for node in nodes where node.kind == .note && known.insert(node.group).inserted { seen.append(node.group) }
        return VaultMapGraph(nodes: nodes, edges: buildEdges(), groups: Array(seen.prefix(10)), orphans: Set(store.orphans.map(\.id)))
    }

    private func buildNodes() -> [VaultMapNode] {
        let notes = store.sortedNotes
        var nodes = store.folders.enumerated().map { index, path in
            VaultMapNode(id: "f:" + path, kind: .folder, ref: path, title: store.folderName(path), group: path.split(separator: "/").first.map(String.init) ?? path, weight: store.noteCount(in: path), seed: Double(index) * 1.7)
        }
        nodes += notes.enumerated().map { index, note in
            VaultMapNode(id: "n:" + note.id, kind: .note, ref: note.id, title: note.title, group: note.property("project") ?? (note.topFolder == note.title ? "Vault" : note.topFolder), weight: store.backlinks(note.id).count, seed: Double(index) * 2.3 + 0.5)
        }
        return nodes
    }

    private func buildEdges() -> [VaultMapEdge] {
        var edges: [VaultMapEdge] = []
        for note in store.sortedNotes {
            for target in store.outlinks(note.id).resolved {
                edges.append(VaultMapEdge(from: "n:" + note.id, to: "n:" + target.id, spoke: false))
            }
            if !note.folder.isEmpty { edges.append(VaultMapEdge(from: "f:" + note.folder, to: "n:" + note.id, spoke: true)) }
        }
        for folder in store.folders {
            let parent = folder.split(separator: "/").dropLast().joined(separator: "/")
            if !parent.isEmpty { edges.append(VaultMapEdge(from: "f:" + parent, to: "f:" + folder, spoke: true)) }
        }
        return edges
    }

    private var focusSteps: [String: Int]? {
        guard let focusID else { return nil }
        return store.neighbourhood(focusID, depth: focusDepth)
    }

    private var visibleNodes: [VaultMapNode] {
        let orphans = graph.orphans
        let steps = focusSteps
        return allNodes.filter { node in
            if let steps { return node.kind == .note && steps[node.ref] != nil }
            if node.kind == .folder { return !hideFolders && !orphansOnly && project == nil }
            guard let note = store.note(node.ref) else { return false }
            if hideDaily && note.isDaily { return false }
            if orphansOnly && !orphans.contains(note.id) { return false }
            if let project, node.group != project { return false }
            return true
        }
    }

    private func tint(_ group: String) -> Color {
        let index = groups.firstIndex(of: group) ?? abs(group.hashValue) % Self.tints.count
        return Color(hex: Self.tints[index % Self.tints.count])
    }

    // MARK: Body

    var body: some View {
        let nodes = visibleNodes
        let ids = Set(nodes.map(\.id))
        let edges = allEdges.filter { ids.contains($0.from) && ids.contains($0.to) }
        let links = edges.filter { !$0.spoke }.count

        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    draw(context: &context, size: size, nodes: nodes, edges: edges, time: timeline.date)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(nodes: nodes).simultaneously(with: magnifyGesture))
            .onTapGesture { location in tap(at: location, nodes: nodes) }
            .onAppear { viewSize = geometry.size }
            .onChange(of: geometry.size) { _, size in viewSize = size }
            .accessibilityElement()
            .accessibilityLabel("Map of \(nodes.count) notes and folders")
            .accessibilityHint("Use the search field to find and open a note")
        }
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .top, spacing: 0) { topBar(count: nodes.filter { $0.kind == .note }.count, links: links) }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .kScreen(glowAt: UnitPoint(x: 0.5, y: 0.45))
        .sheet(item: $peek) { node in
            VaultPeekSheet(node: node) { action in
                peek = nil
                switch action {
                case .open(let id): openInBrowse(id)
                case .around(let id): setFocus(id)
                case .folder(let path):
                    Task {
                        try? await Task.sleep(for: .seconds(0.35))
                        peek = allNodes.first { $0.id == "f:" + path }
                    }
                }
            }
            .environment(nav)
        }
        .overlay {
            if laying {
                VaultLiveLine(text: "Laying out the map")
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: start)
        .onChange(of: store.notes) {
            guard didStart else { return }
            let fresh = buildGraph()
            graph = fresh
            // Opened before the list arrived, or new notes since: lay it out again. A run still going
            // was for the old notes, so it is replaced too.
            if laying || layout.isEmpty || fresh.nodes.contains(where: { layout[$0.id] == nil }) {
                relayout(fresh)
            }
        }
        .animation(Motion.snappy, value: focusID)
        .animation(Motion.snappy, value: orphansOnly)
        .animation(Motion.snappy, value: hideFolders)
        .animation(Motion.snappy, value: hideDaily)
        .animation(Motion.snappy, value: project)
    }

    // MARK: Drawing

    private func position(_ node: VaultMapNode, time: Date) -> CGPoint {
        let base = layout[node.id] ?? .zero
        if reduceMotion || dragging == node.id { return base }
        let t = time.timeIntervalSince(started)
        let settle = min(1, t / 0.9)
        let eased = 1 - pow(1 - settle, 3)
        let drift = CGPoint(x: sin(t * 0.5 + node.seed) * 2.5, y: cos(t * 0.42 + node.seed) * 2.5)
        return CGPoint(x: base.x * eased + drift.x, y: base.y * eased + drift.y)
    }

    private func screen(_ world: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + offset.width + world.x * scale, y: size.height / 2 + offset.height + world.y * scale)
    }

    private func world(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: (point.x - size.width / 2 - offset.width) / scale, y: (point.y - size.height / 2 - offset.height) / scale)
    }

    private func radius(_ node: VaultMapNode) -> CGFloat {
        node.kind == .folder ? 7 + CGFloat(min(node.weight, 12)) * 0.6 : 6 + CGFloat(min(node.weight, 8)) * 1.6
    }

    private func draw(context: inout GraphicsContext, size: CGSize, nodes: [VaultMapNode], edges: [VaultMapEdge], time: Date) {
        // Everything here is one pass over the nodes or the edges per frame, never a pass inside a pass.
        // Nodes not laid out yet are not drawn, so a vault being laid out never stacks in the middle.
        var points: [String: CGPoint] = [:]
        points.reserveCapacity(nodes.count)
        for node in nodes where layout[node.id] != nil { points[node.id] = screen(position(node, time: time), size: size) }
        let around: Set<String> = selected.map { id in
            var set: Set<String> = []
            for edge in edges where edge.from == id || edge.to == id { set.insert(edge.from); set.insert(edge.to) }
            return set
        } ?? []
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40)
        // A large vault: labels only for the selected note, its neighbours and well-linked notes.
        let large = graph.nodes.count > VaultMapLayout.forceLimit

        for edge in edges {
            guard let a = points[edge.from], let b = points[edge.to] else { continue }
            let box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x) + 1, height: abs(a.y - b.y) + 1)
            guard box.intersects(bounds) else { continue }
            let lit = selected != nil && (edge.from == selected || edge.to == selected)
            let dim = selected != nil && !lit
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            let color: Color = edge.spoke ? Palette.inkFaint.opacity(dim ? 0.06 : 0.16) : (lit ? Palette.gold : Palette.ink.opacity(dim ? 0.08 : 0.3))
            context.stroke(path, with: .color(color), lineWidth: lit ? 2 : (edge.spoke ? 0.8 : 1.1))
            if !edge.spoke {
                let dx = b.x - a.x, dy = b.y - a.y
                let length = max(1, sqrt(dx * dx + dy * dy))
                let ux = dx / length, uy = dy / length
                let tipBack: CGFloat = 14 * min(1.4, max(0.7, scale))
                let tip = CGPoint(x: b.x - ux * tipBack, y: b.y - uy * tipBack)
                var tick = Path()
                tick.move(to: CGPoint(x: tip.x - ux * 6 - uy * 4, y: tip.y - uy * 6 + ux * 4))
                tick.addLine(to: tip)
                tick.addLine(to: CGPoint(x: tip.x - ux * 6 + uy * 4, y: tip.y - uy * 6 - ux * 4))
                context.stroke(tick, with: .color(color), lineWidth: lit ? 1.6 : 1)
            }
        }

        for node in nodes {
            guard let point = points[node.id], bounds.contains(point) else { continue }
            let r = radius(node) * min(1.6, max(0.7, scale))
            let isSelected = node.id == selected
            let dim = selected != nil && !isSelected && !around.contains(node.id)
            let fill = (node.kind == .folder ? Palette.inkDim : tint(node.group)).opacity(dim ? 0.25 : 1)
            let shape: Path
            if node.kind == .folder {
                shape = Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
            } else {
                var triangle = Path()
                triangle.move(to: CGPoint(x: point.x, y: point.y - r * 1.15))
                triangle.addLine(to: CGPoint(x: point.x + r, y: point.y + r * 0.75))
                triangle.addLine(to: CGPoint(x: point.x - r, y: point.y + r * 0.75))
                triangle.closeSubpath()
                shape = triangle
            }
            if isSelected {
                context.fill(Path(ellipseIn: CGRect(x: point.x - r - 9, y: point.y - r - 9, width: (r + 9) * 2, height: (r + 9) * 2)), with: .color(Palette.gold.opacity(0.22)))
            }
            context.fill(shape, with: .color(fill))
            if node.kind == .folder {
                context.stroke(shape, with: .color(Palette.ground), lineWidth: 1.5)
            }
            let showLabel = large
                ? isSelected || around.contains(node.id) || (scale > 0.75 && node.weight >= 3)
                : isSelected || around.contains(node.id) || scale > 1.15 || (scale > 0.75 && node.weight >= 3) || focusID != nil
            if showLabel && !dim {
                let label = Text(node.title)
                    .font(KFont.ui(isSelected ? 13.5 : 12, isSelected ? .semibold : .regular, relativeTo: .caption))
                    .foregroundStyle(isSelected ? Palette.ink : Palette.inkDim)
                context.draw(label, at: CGPoint(x: point.x, y: point.y + r + 10), anchor: .center)
            }
        }
    }

    // MARK: Gestures

    private func hit(_ location: CGPoint, nodes: [VaultMapNode]) -> VaultMapNode? {
        let size = viewSize
        var best: (VaultMapNode, CGFloat)?
        for node in nodes {
            guard let base = layout[node.id] else { continue }
            let point = screen(base, size: size)
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < max(24, radius(node) * scale + 10), distance < (best?.1 ?? .infinity) { best = (node, distance) }
        }
        return best?.0
    }

    private func dragGesture(nodes: [VaultMapNode]) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragging == nil && !panning {
                    if let node = hit(value.startLocation, nodes: nodes) {
                        dragging = node.id
                        Haptics.select()
                    } else {
                        panning = true
                    }
                }
                if let dragging {
                    layout[dragging] = world(value.location, size: viewSize)
                } else {
                    offset = CGSize(width: baseOffset.width + value.translation.width, height: baseOffset.height + value.translation.height)
                }
            }
            .onEnded { _ in
                dragging = nil
                panning = false
                baseOffset = offset
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let next = min(3, max(0.15, baseScale * value.magnification))
                let ratio = next / scale
                scale = next
                offset = CGSize(width: offset.width * ratio, height: offset.height * ratio)
            }
            .onEnded { _ in
                baseScale = scale
                baseOffset = offset
            }
    }

    private func tap(at location: CGPoint, nodes: [VaultMapNode]) {
        if let node = hit(location, nodes: nodes) {
            Haptics.tap()
            selected = node.id
            peek = node
        } else if selected != nil {
            Haptics.select()
            selected = nil
        }
    }

    // MARK: Actions

    private func start() {
        guard !didStart else { return }
        didStart = true
        started = .now
        if let focus {
            selected = "n:" + focus
        }
        let fresh = buildGraph()
        graph = fresh
        relayout(fresh)
        if nav.debug == .focus, let focus {
            nav.debug = .none
            setFocus(focus)
        } else if nav.debug == .peek {
            nav.debug = .none
            let id = focus ?? "Projects/Bike shop/Launch plan"
            selected = "n:" + id
            peek = fresh.nodes.first { $0.id == "n:" + id }
        } else if let focus {
            centerWhenLaid = "n:" + focus
        }
    }

    /// Lay the graph out off the main actor, from plain values. Only the newest run's result is used.
    private func relayout(_ fresh: VaultMapGraph) {
        layoutRun += 1
        let run = layoutRun
        let nodes = fresh.nodes
        let edges = fresh.edges
        laying = true
        Task {
            let points = await Task.detached(priority: .userInitiated) {
                VaultMapLayout.compute(nodes: nodes, edges: edges)
            }.value
            guard run == layoutRun else { return }
            layout = points
            laying = false
            started = reduceMotion ? .distantPast : .now
            if let focusID { placeRings(around: focusID) }
            if let id = centerWhenLaid, layout[id] != nil {
                centerWhenLaid = nil
                center(on: id)
            }
            if fitWhenLaid {
                fitWhenLaid = false
                fit()
            }
        }
    }

    /// Focus mode: the note in the middle and its neighbours on rings, over whatever layout is there.
    private func placeRings(around id: String) {
        let steps = store.neighbourhood(id, depth: focusDepth)
        for (note, point) in VaultMapLayout.rings(center: id, steps: steps) { layout["n:" + note] = point }
    }

    private func setFocus(_ id: String?) {
        Haptics.select()
        withAnimation(Motion.sheet) {
            focusID = id
            if let id {
                placeRings(around: id)
                selected = "n:" + id
                scale = 0.85
                baseScale = scale
                offset = .zero
                baseOffset = .zero
            } else {
                fitWhenLaid = true
                relayout(graph)
            }
        }
        started = reduceMotion ? .distantPast : .now
    }

    private func center(on nodeID: String) {
        guard let point = layout[nodeID] else { return }
        withAnimation(Motion.sheet) {
            scale = max(scale, 1.1)
            baseScale = scale
            offset = CGSize(width: -point.x * scale, height: -point.y * scale)
            baseOffset = offset
        }
    }

    private func fit() {
        let points = visibleNodes.compactMap { layout[$0.id] }
        guard !points.isEmpty, viewSize.width > 0 else { return }
        let xs = points.map(\.x), ys = points.map(\.y)
        let width = (xs.max()! - xs.min()!) + 80
        let height = (ys.max()! - ys.min()!) + 80
        let next = min(3, max(0.15, min(viewSize.width / width, (viewSize.height - 240) / height)))
        withAnimation(Motion.sheet) {
            scale = next
            baseScale = next
            offset = CGSize(width: -(xs.max()! + xs.min()!) / 2 * next, height: -(ys.max()! + ys.min()!) / 2 * next)
            baseOffset = offset
        }
    }

    private func zoom(by factor: CGFloat) {
        Haptics.select()
        withAnimation(Motion.snappy) {
            let next = min(3, max(0.15, scale * factor))
            let ratio = next / scale
            scale = next
            baseScale = next
            offset = CGSize(width: offset.width * ratio, height: offset.height * ratio)
            baseOffset = offset
        }
    }

    private func openInBrowse(_ id: String) {
        if case .map = nav.path.last { nav.path.removeLast() }
        nav.open(id)
    }

    // MARK: Bars

    private func topBar(count: Int, links: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FilesHeader(title: "Map", subtitle: "\(count) notes · \(links) connections" + (focusID != nil ? " · depth \(focusDepth)" : ""), back: { dismiss() }) {
                GlassIconButton(symbol: "folder", label: "All folders") {
                    peek = VaultMapNode(id: "f:", kind: .folder, ref: "", title: "Vault", group: "", weight: store.notes.count, seed: 0)
                }
                GlassIconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Fit view") { fit() }
            }
            .background(Color.clear)
            VStack(alignment: .leading, spacing: 8) {
                FilesSearchField(text: $query, prompt: "Find a note or folder") {
                    if let first = searchHits.first { pick(first) }
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchList
                } else if let focusID {
                    focusBar(focusID)
                } else {
                    filters
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .background { HeaderFade() }
    }

    private var searchHits: [VaultMapNode] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(allNodes.filter { $0.title.lowercased().contains(q) || $0.ref.lowercased().contains(q) }.prefix(20))
    }

    private var searchList: some View {
        let hits = searchHits
        return VStack(spacing: 0) {
            if hits.isEmpty {
                Text("No matching notes or folders")
                    .font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(hits) { node in
                            Button { pick(node) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: node.kind == .folder ? "folder" : "doc.text").foregroundStyle(Palette.goldText).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(node.title).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                                        Text(node.ref).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle(scale: 0.99))
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .kGlass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: Palette.glassTintStrong)
    }

    private func pick(_ node: VaultMapNode) {
        query = ""
        if !visibleNodes.contains(node) {
            orphansOnly = false
            hideFolders = false
            hideDaily = false
            project = nil
            focusID = nil
        }
        selected = node.id
        center(on: node.id)
        peek = node
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                FilterPill(title: "Orphans", on: orphansOnly) { orphansOnly.toggle() }
                FilterPill(title: "Hide folders", on: hideFolders) { hideFolders.toggle() }
                FilterPill(title: "Hide daily notes", on: hideDaily) { hideDaily.toggle() }
                Palette.line.frame(width: 1, height: 24).padding(.horizontal, 4)
                ForEach(groups, id: \.self) { group in
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) { project = project == group ? nil : group }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(tint(group)).frame(width: 9, height: 9)
                            Text(group).font(KFont.ui(13.5, project == group ? .semibold : .regular, relativeTo: .footnote))
                                .foregroundStyle(project == nil || project == group ? Palette.ink : Palette.inkFaint)
                                .fixedSize()
                        }
                        .padding(.horizontal, 11)
                        .frame(minHeight: 36)
                        .background(project == group ? Palette.ink.opacity(0.14) : Color.clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Only \(group)")
                    .accessibilityAddTraits(project == group ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func focusBar(_ id: String) -> some View {
        HStack(spacing: 6) {
            Text("Around \(store.note(id)?.title ?? "")")
                .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            ForEach(1...3, id: \.self) { step in
                FilterPill(title: "\(step)", on: focusDepth == step) {
                    focusDepth = step
                    setFocus(id)
                }
                .accessibilityLabel("Depth \(step)")
            }
            FilterPill(title: "Whole vault", on: false) { setFocus(nil) }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .kGlass(Capsule())
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                if let selected, selected.hasPrefix("n:") {
                    openInBrowse(String(selected.dropFirst(2)))
                } else {
                    dismiss()
                }
            } label: {
                Label("Browse", systemImage: "list.bullet")
                    .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .kGlass(Capsule(), interactive: true)
            .accessibilityHint("Back to the note list")
            Spacer()
            Text("Drag to explore · Pinch to zoom · Tap to read")
                .font(KFont.ui(12, relativeTo: .caption))
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
            GlassEffectContainer(spacing: 6) {
                VStack(spacing: 6) {
                    GlassIconButton(symbol: "plus", label: "Zoom in", size: 40) { zoom(by: 1.35) }
                    GlassIconButton(symbol: "minus", label: "Zoom out", size: 40) { zoom(by: 1 / 1.35) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Peek sheet

enum VaultPeekAction {
    case open(String)
    case around(String)
    case folder(String)
}

/// Tapping a node: a short look at the note or folder, with Open and Show around.
struct VaultPeekSheet: View {
    let node: VaultMapNode
    let act: (VaultPeekAction) -> Void
    @State private var store = VaultStore.shared

    var body: some View {
        FittedSheet(estimate: 360) {
            VStack(alignment: .leading, spacing: 14) {
                if node.kind == .note, let note = store.note(node.ref) {
                    noteBody(note)
                } else {
                    folderBody
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 24)
        }
    }

    private func noteBody(_ note: VaultNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(note.title).font(KFont.display(30)).foregroundStyle(Palette.ink)
            Text("\(note.folder.isEmpty ? "Vault" : note.folder) · edited \(FilesDates.ago(note.edited).lowercased())")
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
            if !note.properties.isEmpty { VaultPropertyPills(note: note, compact: true) }
            Text(VaultMarkdown.plain(note.content.components(separatedBy: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }.prefix(3).joined(separator: " ")))
                .font(KFont.ui(15.5))
                .foregroundStyle(Palette.inkDim)
                .lineLimit(3)
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    act(.around(note.id))
                } label: {
                    Text("Show around")
                        .font(KFont.ui(16, .medium))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Palette.ink.opacity(0.09), in: Capsule())
                }
                .buttonStyle(PressStyle())
                GoldButton(title: "Open") { act(.open(note.id)) }
            }
            .padding(.top, 4)
        }
    }

    private var folderBody: some View {
        let children = store.children(of: node.ref)
        let folderRows: [(id: String, title: String, folder: Bool)] = children.folders.map { path in (id: path, title: store.folderName(path), folder: true) }
        let noteRows: [(id: String, title: String, folder: Bool)] = children.notes.map { note in (id: note.id, title: note.title, folder: false) }
        let rows = folderRows + noteRows
        return VStack(alignment: .leading, spacing: 12) {
            Text(node.title).font(KFont.display(30)).foregroundStyle(Palette.ink)
            Text("\(store.noteCount(in: node.ref)) notes").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            if rows.isEmpty {
                Text("Empty folder.").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(30).enumerated()), id: \.offset) { index, row in
                        Button {
                            Haptics.tap()
                            act(row.folder ? .folder(row.id) : .open(row.id))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: row.folder ? "folder" : "doc.text").foregroundStyle(Palette.goldText).frame(width: 24)
                                Text(row.title).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if index < min(rows.count, 30) - 1 { Palette.line.frame(height: 1).padding(.leading, 50) }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                    }
                }
                .kCard(radius: 18)
            }
        }
    }
}
