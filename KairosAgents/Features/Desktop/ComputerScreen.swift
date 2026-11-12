import SwiftUI

nonisolated enum ComputerStart: Hashable, Sendable { case watch, control, steps, closed }

/// See and steer the desktop screen. Kairos works on it; take over to click, drag, scroll and type yourself.
struct ComputerScreen: View {
    var start: ComputerStart = .watch

    @State private var store = ComputerStore()
    @State private var mode: PointerMode = .click
    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var scrollBase: CGFloat = 0
    @State private var ripples: [ComputerRipple] = []
    @State private var keyboardUp = false
    @State private var draft = ""
    @FocusState private var typing: Bool
    @State private var showSteps = false
    @State private var showReview = false
    @State private var confirmStop = false
    @State private var toast: String?
    @State private var started = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            statusLine
            screenView
            if store.hasControl {
                controlPanel
            } else if store.control == .kairos {
                watchPanel
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Computer", subtitle: "Studio PC") {
                GlassIconButton(symbol: "list.number", label: "Steps Kairos took") { showSteps = true }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.hasControl && keyboardUp { keyboardBar }
        }
        .kScreen()
        .machineToast($toast)
        .animation(Motion.snappy, value: store.control)
        .animation(Motion.snappy, value: keyboardUp)
        .sheet(isPresented: $showSteps) {
            ComputerStepsSheet(runs: store.runs) {
                showSteps = false
                Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    showReview = true
                }
            }
        }
        .sheet(isPresented: $showReview) {
            ComputerSkillReview(steps: max(store.recordedSteps, 3)) { saved in
                showReview = false
                toast = saved ? "Saved as a skill. Find it in the Tool Store." : "Recording discarded."
            }
        }
        .confirmationDialog("Stop the computer?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { store.stop() }
            Button("Keep it running", role: .cancel) {}
        } message: {
            Text("Kairos stops working on your desktop. The last picture stays here.")
        }
        .onAppear {
            guard !started else { return }
            started = true
            switch start {
            case .watch: break
            case .control: store.takeOver(); keyboardUp = true
            case .steps: showSteps = true
            case .closed: store.stop()
            }
        }
    }

    // MARK: Status

    private var statusLine: some View {
        HStack(spacing: 10) {
            switch store.control {
            case .kairos: PulsingDot(color: Palette.working, size: 8)
            case .you: Circle().fill(Palette.gold).frame(width: 8, height: 8)
            case .closed: Circle().fill(Palette.inkFaint).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(stateTitle)
                    .font(KFont.ui(16, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Text(store.lastAction)
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            if store.recording {
                HStack(spacing: 6) {
                    PulsingDot(color: Palette.danger, size: 7)
                    Text("Recording").font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.danger)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .kCard(radius: 18)
        .accessibilityElement(children: .combine)
    }

    private var stateTitle: String {
        switch store.control {
        case .kairos: "Kairos has control"
        case .you: "You have control"
        case .closed: "Computer closed"
        }
    }

    // MARK: Screen

    private var screenView: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                ComputerFrame(typed: store.typed, scroll: store.scroll, showCaret: store.hasControl)
                    .scaleEffect(zoom)
                    .offset(pan)
                ForEach(ripples) { ripple in
                    RippleMark(reduceMotion: reduceMotion)
                        .position(ripple.point)
                }
                if store.control == .closed {
                    ZStack {
                        Color.black.opacity(0.45)
                        VStack(spacing: 10) {
                            Text("Computer closed")
                                .font(KFont.ui(17, .semibold))
                                .foregroundStyle(Palette.cream)
                            DeskPillButton(title: "Watch again", symbol: "play.fill", tint: Palette.cream) {
                                store.reconnect()
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(store.recording ? Palette.danger : (store.hasControl ? Palette.gold : Palette.line), lineWidth: store.hasControl || store.recording ? 2 : 1)
            )
            .contentShape(Rectangle())
            .gesture(pointer(size))
            .simultaneousGesture(pinch)
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your desktop screen")
        .accessibilityValue(store.hasControl ? "You have control. Tap to click." : stateTitle)
        .accessibilityAction(named: "Click the middle of the screen") {
            if store.hasControl { store.click(at: CGPoint(x: 640, y: 400)) }
        }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(1, pinchBase * value.magnification), 3)
            }
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

    private func pointer(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let moved = hypot(value.translation.width, value.translation.height)
                guard moved > 8 else { return }
                if panning {
                    pan = clampPan(CGSize(width: panBase.width + value.translation.width, height: panBase.height + value.translation.height), size)
                } else if store.hasControl && mode == .scroll {
                    store.scroll = min(max(0, scrollBase - value.translation.height * 1.4), 260)
                }
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height)
                if moved <= 8 {
                    tap(at: value.location, size)
                } else if panning {
                    panBase = pan
                } else if store.hasControl && mode == .scroll {
                    let amount = store.scroll - scrollBase
                    scrollBase = store.scroll
                    store.scrollBy(0)
                    store.lastAction = amount > 0 ? "Scroll down" : "Scroll up"
                } else if store.hasControl {
                    let from = map(value.startLocation, size)
                    let to = map(value.location, size)
                    store.drag(from: from, to: to)
                    addRipple(value.location)
                }
            }
    }

    /// Dragging moves the view when watching, or in Move view, and only when zoomed in.
    private var panning: Bool {
        zoom > 1.01 && (!store.hasControl || mode == .move)
    }

    private func tap(at point: CGPoint, _ size: CGSize) {
        switch store.control {
        case .you:
            guard mode == .click else {
                toast = mode == .scroll ? "Drag up or down to scroll." : "Drag to move the view."
                return
            }
            store.click(at: map(point, size))
            addRipple(point)
            Haptics.tap()
        case .kairos:
            toast = "Take over to click on your desktop."
        case .closed:
            break
        }
    }

    /// From a point on the phone to the PC's 1280 by 800 screen, through the zoom and pan.
    private func map(_ point: CGPoint, _ size: CGSize) -> CGPoint {
        let cx = size.width / 2
        let cy = size.height / 2
        let x = (point.x - cx - pan.width) / zoom + cx
        let y = (point.y - cy - pan.height) / zoom + cy
        return CGPoint(x: min(max(0, x / size.width * 1280), 1280), y: min(max(0, y / size.height * 800), 800))
    }

    private func clampPan(_ proposed: CGSize, _ size: CGSize) -> CGSize {
        let maxX = size.width * (zoom - 1) / 2
        let maxY = size.height * (zoom - 1) / 2
        return CGSize(width: min(max(-maxX, proposed.width), maxX), height: min(max(-maxY, proposed.height), maxY))
    }

    private func addRipple(_ point: CGPoint) {
        let ripple = ComputerRipple(point: point)
        ripples.append(ripple)
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            ripples.removeAll { $0.id == ripple.id }
        }
    }

    // MARK: Watching

    private var watchPanel: some View {
        VStack(spacing: 10) {
            if zoom > 1.01 {
                NoteLine(text: "Drag to look around. Pinch out to see the whole screen.", symbol: "arrow.up.and.down.and.arrow.left.and.right")
            } else {
                NoteLine(text: "Pinch to zoom in. Take over to click and type yourself.", symbol: "hand.draw")
            }
            GoldButton(title: "Take over") {
                store.takeOver()
                toast = "You have control. Kairos waits until you hand back."
            }
            QuietButton(title: "Stop") { confirmStop = true }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: In control

    private var controlPanel: some View {
        VStack(spacing: 12) {
            GlassSwitch(items: PointerMode.allCases, selection: $mode) { $0.rawValue }
            Text(modeHint)
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity)
            if !(keyboardUp && typing) {
                HStack(spacing: 8) {
                    controlButton(symbol: "keyboard", title: keyboardUp ? "Hide keys" : "Keyboard", on: keyboardUp) {
                        keyboardUp.toggle()
                        typing = keyboardUp
                    }
                    controlButton(symbol: store.recording ? "stop.circle" : "record.circle", title: store.recording ? "Stop" : "Record", on: store.recording) {
                        if store.toggleRecording() { showReview = true }
                    }
                    controlButton(symbol: "hand.raised", title: "Hand back", on: false) {
                        keyboardUp = false
                        typing = false
                        store.handBack()
                    }
                }
                NoteLine(text: "Ctrl+Esc opens desktop apps.", symbol: "lightbulb")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var modeHint: String {
        switch mode {
        case .click: "Tap to click. Drag to drag. Pinch to zoom."
        case .scroll: "Drag up or down to scroll the window under it."
        case .move: zoom > 1.01 ? "Drag to look around the screen." : "Pinch to zoom in first, then drag to look around."
        }
    }

    private func controlButton(symbol: String, title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(Motion.snappy) { action() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                Text(title).font(KFont.ui(13, .medium, relativeTo: .footnote)).lineLimit(1)
            }
            .foregroundStyle(on ? Palette.onGold : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.surfaceRaised), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.line, lineWidth: on ? 0 : 1))
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Keyboard

    private var keyboardBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(ComputerKey.all) { key in
                        let held = store.modifiers.contains(key.name)
                        Button {
                            store.key(key.name)
                        } label: {
                            Group {
                                if let symbol = key.symbol {
                                    Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                                } else {
                                    Text(key.label).font(KFont.ui(14, .medium, relativeTo: .footnote))
                                }
                            }
                            .foregroundStyle(held ? Palette.onGold : Palette.ink)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(held ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.surfaceRaised), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                        }
                        .buttonStyle(PressStyle(scale: 0.9))
                        .accessibilityLabel(key.spoken)
                        .accessibilityAddTraits(held ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 8) {
                TextField("Type on your PC", text: $draft)
                    .font(KFont.ui(16.5))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .submitLabel(.return)
                    .onSubmit {
                        store.key("Enter")
                        typing = true
                    }
                    .onChange(of: draft) { _, new in
                        guard !new.isEmpty else { return }
                        store.type(new)
                        draft = ""
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .kGlass(Capsule())
                GlassIconButton(symbol: "keyboard.chevron.compact.down", label: "Hide keyboard", size: 46) {
                    typing = false
                    keyboardUp = false
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Palette.ground.opacity(0.92).ignoresSafeArea(edges: .bottom))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// One key on the key row.
nonisolated struct ComputerKey: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var label: String
    var symbol: String? = nil
    var spoken: String

    static let all: [ComputerKey] = [
        ComputerKey(name: "Esc", label: "Esc", spoken: "Escape"),
        ComputerKey(name: "Tab", label: "Tab", spoken: "Tab"),
        ComputerKey(name: "Ctrl", label: "Ctrl", spoken: "Control, hold for the next key"),
        ComputerKey(name: "Alt", label: "Alt", spoken: "Alt, hold for the next key"),
        ComputerKey(name: "Win", label: "Win", spoken: "Windows key, hold for the next key"),
        ComputerKey(name: "Left", label: "Left", symbol: "arrow.left", spoken: "Left arrow"),
        ComputerKey(name: "Up", label: "Up", symbol: "arrow.up", spoken: "Up arrow"),
        ComputerKey(name: "Down", label: "Down", symbol: "arrow.down", spoken: "Down arrow"),
        ComputerKey(name: "Right", label: "Right", symbol: "arrow.right", spoken: "Right arrow"),
        ComputerKey(name: "Enter", label: "Enter", symbol: "return", spoken: "Enter"),
        ComputerKey(name: "Backspace", label: "Backspace", symbol: "delete.left", spoken: "Backspace"),
        ComputerKey(name: "Ctrl+C", label: "Ctrl+C", spoken: "Copy, control C"),
        ComputerKey(name: "Ctrl+V", label: "Ctrl+V", spoken: "Paste, control V"),
    ]
}

/// The ring that shows where a click landed.
struct RippleMark: View {
    let reduceMotion: Bool
    @State private var out = false

    var body: some View {
        Circle()
            .strokeBorder(Palette.gold, lineWidth: 2.5)
            .background(Circle().fill(Palette.gold.opacity(out ? 0 : 0.35)))
            .frame(width: 34, height: 34)
            .scaleEffect(out ? 1.8 : 0.6)
            .opacity(out ? 0 : 1)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(reduceMotion ? .linear(duration: 0.6) : .easeOut(duration: 0.6)) { out = true }
            }
            .accessibilityHidden(true)
    }
}
