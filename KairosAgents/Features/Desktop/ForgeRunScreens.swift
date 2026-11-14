import SwiftUI
import UIKit

nonisolated struct TerminalPane: Identifiable, Hashable, Sendable {
    let id = UUID()
    var name: String
    var output: String
    var closed = false
}

/// The session terminal, with the keys a phone keyboard lacks: Tab, Esc, Ctrl and the arrows.
struct ForgeTerminalScreen: View {
    let sessionID: String
    @State private var store = ForgeStore.shared
    @State private var panes: [TerminalPane] = [TerminalPane(name: "Terminal 1", output: ForgeSample.terminalStart)]
    @State private var current = 0
    @State private var line = ""
    @State private var ctrl = false
    @State private var history: [String] = ["npm run dev"]
    @State private var historyIndex: Int?
    @State private var go: DesktopRoute?
    @State private var toast: String?
    @FocusState private var typing: Bool

    private var prompt: String { "PS \(store.project(store.session(sessionID)?.projectID ?? "")?.path ?? "C:")> " }
    private var pane: TerminalPane { panes[min(current, panes.count - 1)] }

    var body: some View {
        // Paired with a desktop: no shell on the phone, and nothing is sent.
        if DeskForgeLive.shared.on {
            DeskChangesLineScreen(title: "Terminal", subtitle: DeskForgeLive.shared.session(sessionID)?.title,
                                  line: "Use the terminal in Kairos on your desktop")
        } else {
            sampleBody
        }
    }

    private var sampleBody: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(pane.output + (pane.closed ? "" : "\n" + prompt + line + "_"))
                            .font(CodeFont.mono(13))
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if pane.closed {
                            Text("Terminal closed.").font(KFont.ui(14, .medium)).foregroundStyle(Palette.inkFaint).padding(.top, 10)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(14)
                }
                .defaultScrollAnchor(.bottom)
                .background(Palette.groundDeep.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .padding(.horizontal, 12)
                .onTapGesture { typing = true }
                .onChange(of: pane.output) { withAnimation(Motion.snappy) { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            if pane.output.contains("http://localhost:5173") {
                Button { go = .preview(sessionID) } label: {
                    Label("Open http://localhost:5173/ in Preview", systemImage: "link")
                        .font(KFont.ui(14, .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(minHeight: 40)
                }
                .padding(.top, 4)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { inputArea }
        .kScreen()
        .navigationDestination(item: $go) { route in DesktopRouteView(route: route) }
        .machineToast($toast)
    }

    private var header: some View {
        VStack(spacing: 8) {
            ScreenHeader(title: "Terminal", subtitle: store.session(sessionID)?.title) {
                GlassIconButton(symbol: "plus", label: "New terminal") {
                    panes.append(TerminalPane(name: "Terminal \(panes.count + 1)", output: "Windows PowerShell"))
                    current = panes.count - 1
                    typing = true
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(panes.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 4) {
                            Button {
                                Haptics.select()
                                current = index
                            } label: {
                                Text(item.name)
                                    .font(KFont.ui(14, index == current ? .semibold : .regular))
                                    .foregroundStyle(index == current ? Palette.ink : Palette.inkDim)
                                    .padding(.leading, 14)
                                    .frame(minHeight: 38)
                            }
                            Button {
                                closePane(index)
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.inkFaint)
                                    .frame(width: 32, height: 38)
                            }
                            .accessibilityLabel("Close \(item.name)")
                        }
                        .background(index == current ? Palette.ink.opacity(0.12) : Color.clear, in: Capsule())
                        .kGlass(Capsule())
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 8)
        }
    }

    private var inputArea: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    key("Esc") { send(raw: "^[") }
                    key("Tab") { complete() }
                    key("Ctrl", on: ctrl) { ctrl.toggle() }
                    key("Ctrl C") { interrupt() }
                    keySymbol("arrow.up", "Up") { recall(-1) }
                    keySymbol("arrow.down", "Down") { recall(1) }
                    keySymbol("arrow.left", "Left") { Haptics.tap() }
                    keySymbol("arrow.right", "Right") { Haptics.tap() }
                    keySymbol("doc.on.clipboard", "Paste") {
                        line += UIPasteboard.general.string ?? ""
                    }
                    keySymbol("doc.on.doc", "Copy output") {
                        UIPasteboard.general.string = pane.output
                        toast = "Output copied"
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 8) {
                Text(">").font(CodeFont.mono(15, .bold)).foregroundStyle(Palette.goldText)
                TextField("Type a command", text: $line)
                    .font(CodeFont.mono(15))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .submitLabel(.go)
                    .onSubmit { run() }
                    .onChange(of: line) { _, new in
                        if ctrl, let last = new.last {
                            ctrl = false
                            line = String(new.dropLast())
                            if last.lowercased() == "c" { interrupt() } else if last.lowercased() == "l" { clear() } else { send(raw: "^" + String(last).uppercased()) }
                        }
                    }
                Button(action: run) {
                    Image(systemName: "return")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.onGold)
                        .frame(width: 40, height: 40)
                        .background(Palette.gold, in: Circle())
                }
                .buttonStyle(PressStyle(scale: 0.88))
                .accessibilityLabel("Enter")
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .frame(minHeight: 52)
            .kGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 12)
            .disabled(pane.closed)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func key(_ title: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(CodeFont.mono(14, .semibold))
                .foregroundStyle(on ? Palette.onGold : Palette.ink)
                .padding(.horizontal, 14)
                .frame(minWidth: 48, minHeight: 44)
                .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func keySymbol(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 48, height: 44)
                .background(Palette.ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    private func append(_ text: String) {
        panes[current].output += "\n" + text
    }

    private func send(raw: String) { append(prompt + line + raw) ; line = "" }

    private func interrupt() {
        append(prompt + line + "^C")
        line = ""
    }

    private func clear() { panes[current].output = "" }

    private func complete() {
        let words = ["npm run dev", "npm test", "git status", "ls"]
        if let match = words.first(where: { $0.hasPrefix(line) && $0 != line }), !line.isEmpty { line = match }
    }

    private func recall(_ step: Int) {
        guard !history.isEmpty else { return }
        let next = max(0, min(history.count - 1, (historyIndex ?? history.count) + step))
        historyIndex = next
        line = history[next]
    }

    private func run() {
        let command = line.trimmingCharacters(in: .whitespaces)
        append(prompt + command)
        line = ""
        historyIndex = nil
        guard !command.isEmpty else { return }
        history.append(command)
        switch command {
        case "clear", "cls": clear()
        case "git status": append("On branch \(store.session(sessionID)?.git.branch ?? "main")\n\(store.session(sessionID)?.changes.count ?? 0) files changed")
        case "ls", "dir": append(ForgeSample.tree.map(\.name).joined(separator: "  "))
        case "exit": panes[current].closed = true
        default: append("This is sample data. Connect your desktop to run commands on it.")
        }
    }

    private func closePane(_ index: Int) {
        Haptics.tap()
        if panes.count == 1 {
            panes[0].closed = true
            return
        }
        panes.remove(at: index)
        current = max(0, min(current, panes.count - 1))
    }
}

nonisolated enum PreviewWidth: String, CaseIterable, Hashable, Sendable {
    case desktop = "Desktop", tablet = "Tablet", phone = "Phone"
}

/// The running app's preview, with its address, history, sizes, and logs with Stop and Restart.
struct ForgePreviewScreen: View {
    let sessionID: String
    var showLogs = false
    @State private var store = ForgeStore.shared
    @State private var pathText = "/"
    @State private var history = ["/"]
    @State private var place = 0
    @State private var width: PreviewWidth = .phone
    @State private var logsOpen = false
    @State private var starting = false
    @State private var showRun = false
    @State private var problem: String?
    @State private var go: DesktopRoute?
    @State private var reloads = 0

    private var app: RunningApp? { store.apps(for: sessionID).first }

    var body: some View {
        // Paired with a desktop: the app's status and logs. Its page opens on the desktop only.
        if DeskForgeLive.shared.on {
            DeskChangesAppView(sessionID: sessionID)
        } else {
            sampleBody
        }
    }

    private var sampleBody: some View {
        VStack(spacing: 10) {
            if let app {
                addressBar(app)
                GlassSwitch(items: PreviewWidth.allCases, selection: $width, title: { $0.rawValue })
                if let problem {
                    NoteLine(text: problem, symbol: "exclamationmark.triangle").padding(.horizontal, 20)
                }
                if starting {
                    VStack(spacing: 10) {
                        ProgressView().tint(Palette.gold)
                        Text("Starting app...").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        SamplePage(path: history[place], width: width)
                            .id(reloads)
                            .transition(.opacity)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                DeskEmptyNote(symbol: "play.rectangle", title: "App stopped", text: "Run the app to preview it here.", action: "Run app") { showRun = true }
                    .frame(maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Preview", subtitle: app.map { "localhost:\(String($0.port)) · \($0.title)" } ?? store.session(sessionID)?.title) {
                if app != nil {
                    GlassIconButton(symbol: "text.alignleft", label: "Logs") { logsOpen = true }
                }
            }
        }
        .kScreen()
        .navigationDestination(item: $go) { route in DesktopRouteView(route: route) }
        .sheet(isPresented: $logsOpen) { logsSheet }
        .sheet(isPresented: $showRun) {
            ForgeRunAppSheet { command in
                store.runApp(sessionID, command: command)
                starting = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(Motion.snappy) { starting = false }
                }
            }
        }
        .onAppear { if showLogs { logsOpen = true } }
    }

    private func addressBar(_ app: RunningApp) -> some View {
        HStack(spacing: 4) {
            navButton("chevron.left", "Back", enabled: place > 0) { place -= 1; pathText = history[place] }
            navButton("chevron.right", "Forward", enabled: place < history.count - 1) { place += 1; pathText = history[place] }
            HStack(spacing: 4) {
                Text("localhost:\(String(app.port))").font(CodeFont.mono(13)).foregroundStyle(Palette.inkFaint)
                TextField("/path", text: $pathText)
                    .font(CodeFont.mono(13.5))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(visit)
                    .disabled(starting)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(Palette.ink.opacity(0.08), in: Capsule())
            navButton("arrow.clockwise", "Reload", enabled: !starting) {
                withAnimation(Motion.gentle) { reloads += 1 }
            }
            navButton("globe", "Open in Browse", enabled: !starting) { go = .browse }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .kGlass(Capsule())
        .padding(.horizontal, 12)
    }

    private func navButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Palette.ink : Palette.inkFaint.opacity(0.5))
                .frame(width: 40, height: 44)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func visit() {
        let path = pathText.trimmingCharacters(in: .whitespaces)
        guard path.hasPrefix("/") else {
            problem = "Start the path with a slash, like /products."
            return
        }
        problem = nil
        history = Array(history.prefix(place + 1)) + [path]
        place = history.count - 1
    }

    private var logsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeskSheetTitle(text: "Logs", detail: app.map { $0.command.replacingOccurrences(of: "{port}", with: String($0.port)) })
            ScrollView {
                Text(ForgeSample.appLogs.joined(separator: "\n"))
                    .font(CodeFont.mono(12.5))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .defaultScrollAnchor(.bottom)
            .background(Palette.groundDeep.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(spacing: 10) {
                DeskPillButton(title: "Restart", symbol: "arrow.clockwise") {
                    logsOpen = false
                    starting = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation(Motion.snappy) { starting = false }
                    }
                }
                DeskPillButton(title: "Stop app", symbol: "stop.fill", tint: Palette.danger) {
                    logsOpen = false
                    if let app { withAnimation(Motion.snappy) { store.stopApp(app.id) } }
                }
            }
            NoteLine(text: "Restart asks your PC's approval rules first.")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .kSheet([.medium, .large])
    }
}

/// A drawn page standing in for the running web app (the bike shop sample).
struct SamplePage: View {
    let path: String
    let width: PreviewWidth

    private var columns: Int {
        switch width {
        case .desktop: 3
        case .tablet: 2
        case .phone: 1
        }
    }

    var body: some View {
        let paper = Palette.paper
        let ink = Palette.night
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spoke and Chain").font(.system(size: 17, weight: .bold, design: .serif))
                Spacer()
                Image(systemName: width == .phone ? "line.3.horizontal" : "cart")
            }
            .foregroundStyle(ink)
            Text(path == "/" ? "Bikes for every road" : "Page \(path)")
                .font(.system(size: width == .phone ? 24 : 28, weight: .semibold, design: .serif))
                .foregroundStyle(ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                ForEach(["City bike", "Gravel bike", "Kids bike"], id: \.self) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [Color(hex: Palette.botSand), Color(hex: Palette.botRose)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 90)
                            .overlay(Image(systemName: "bicycle").font(.system(size: 34)).foregroundStyle(ink.opacity(0.6)))
                        Text(item).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                        Text("From 420").font(.system(size: 12)).foregroundStyle(ink.opacity(0.6))
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: width == .phone ? 360 : .infinity)
        .background(paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity)
        .animation(Motion.snappy, value: width)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of the shop site, \(width.rawValue) width")
    }
}

// MARK: - Paired with a desktop

/// What the app screen is asking the person to confirm.
enum DeskChangesAppAsk: String, Identifiable {
    case restart, stop
    var id: String { rawValue }
}

/// The session's running app on the paired desktop: its status and last log lines, with Restart and Stop.
/// The app listens on the desktop only, so its page is not shown here. Starting it is done from the session.
struct DeskChangesAppView: View {
    let sessionID: String
    @State private var live = DeskChangesLive.shared
    @State private var forge = DeskForgeLive.shared
    @State private var ask: DeskChangesAppAsk?
    @State private var notice: String?
    @State private var toast: String?

    private var state: DeskChangesAppState? { live.app(sessionID) }
    private var busy: Bool { live.isBusy("app:" + sessionID) || live.approval(sessionID)?.active == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let line = notice ?? live.note(sessionID) {
                    DeskForgeLine(text: line, action: "OK") {
                        notice = nil
                        live.clearNote(sessionID)
                    }
                }
                if forge.isAdmin, live.gone(sessionID) == nil, let state, state.load == .loaded {
                    content(state)
                } else {
                    DeskChangesGate(sessionID: sessionID, load: state?.load ?? .loading, reading: "Reading this app from your desktop.") {
                        Task { await live.loadApp(sessionID) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable { await live.loadApp(sessionID) }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "App", subtitle: forge.session(sessionID)?.title) {
                GlassIconButton(symbol: "arrow.clockwise", label: "Refresh the app") {
                    Task { await live.loadApp(sessionID) }
                }
            }
        }
        .kScreen()
        .sheet(item: $ask) { item in
            switch item {
            case .restart:
                ConfirmSheet(title: "Restart the app?",
                             detail: "Stops it on your desktop and starts it again with its saved command. Your desktop may ask you to approve the command first.",
                             confirm: "Restart", danger: false) {
                    notice = nil
                    live.startApproval(sessionID, .restart)
                }
            case .stop:
                ConfirmSheet(title: "Stop the app?",
                             detail: "Stops it on your desktop. Anything using it loses its place. You can start it again from the session.",
                             confirm: "Stop app") {
                    Task {
                        let outcome = await live.stopApp(sessionID)
                        if let line = outcome.line {
                            notice = line
                        } else if outcome == .done {
                            Haptics.success()
                            toast = "The app was stopped"
                        }
                    }
                }
            }
        }
        .machineToast($toast)
        .task(id: DeskForgeLive.connectionKey + "|" + sessionID) {
            guard live.on else { return }
            await live.loadApp(sessionID)
            // The status and logs move while the app runs: read them while this screen is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await live.loadApp(sessionID)
            }
        }
    }

    @ViewBuilder
    private func content(_ state: DeskChangesAppState) -> some View {
        let app = state.app
        let running = app?.running == true
        let place = app?.port.map { "On port \($0) on your desktop" } ?? "On your desktop"
        if let stale = live.stale(sessionID) {
            DeskForgeLine(text: stale, action: "Try again") { Task { await live.loadApp(sessionID) } }
        }
        if let approval = live.approval(sessionID), approval.kind == .restart {
            DeskChangesApprovalCard(sessionID: sessionID, approval: approval)
        }
        HStack(spacing: 12) {
            if running {
                PulsingDot(color: app?.ready == true ? Palette.success : Palette.working, size: 8)
            } else {
                Circle().fill(Palette.inkFaint).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(running ? (app?.ready == true ? "Running" : "Starting") : "Stopped")
                    .font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                Text(running ? place : stoppedLine(app))
                    .font(KFont.ui(13.5)).foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .kCard(radius: 20)
        if running {
            HStack(spacing: 10) {
                DeskPillButton(title: "Restart", symbol: "arrow.clockwise") { ask = .restart }
                    .disabled(busy)
                    .opacity(busy ? 0.45 : 1)
                DeskPillButton(title: "Stop app", symbol: "stop.fill", tint: Palette.danger) { ask = .stop }
                    .disabled(busy)
                    .opacity(busy ? 0.45 : 1)
            }
        } else {
            NoteLine(text: "Start the app from this session's actions.", symbol: "play.circle")
        }
        NoteLine(text: "The app's page opens on your desktop only. It listens there, so it cannot be shown here.", symbol: "desktopcomputer")
        logs(state)
    }

    private func stoppedLine(_ app: DeskChangesAppDTO?) -> String {
        if let code = app?.exitCode { return "It exited with code \(code)." }
        return "No app is running for this session."
    }

    @ViewBuilder
    private func logs(_ state: DeskChangesAppState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Logs")
            switch state.logsLoad {
            case .loaded:
                if state.logs.isEmpty {
                    NoteLine(text: "No log lines yet.")
                } else {
                    // Selection stays off: the logs are for reading here, and there is no copy-all.
                    ScrollView {
                        Text(state.logs.suffix(200).joined(separator: "\n"))
                            .font(CodeFont.mono(12.5))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(maxHeight: 380)
                    .background(Palette.groundDeep.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            case .failed(let why):
                DeskForgeLine(text: "The logs could not be read. " + why, action: "Try again") {
                    Task { await live.loadApp(sessionID) }
                }
            case .idle, .loading:
                DeskForgeLine(text: "Reading the logs from your desktop.")
            }
        }
    }
}
