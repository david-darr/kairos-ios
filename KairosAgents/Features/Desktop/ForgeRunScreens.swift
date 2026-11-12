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
                EmptyNote(symbol: "play.rectangle", title: "App stopped", text: "Run the app to preview it here.", action: "Run app") { showRun = true }
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
            SheetTitle(text: "Logs", detail: app.map { $0.command.replacingOccurrences(of: "{port}", with: String($0.port)) })
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
                PillButton(title: "Restart", symbol: "arrow.clockwise") {
                    logsOpen = false
                    starting = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation(Motion.snappy) { starting = false }
                    }
                }
                PillButton(title: "Stop app", symbol: "stop.fill", tint: Palette.danger) {
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
