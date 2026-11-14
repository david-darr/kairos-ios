import SwiftUI

/// The Cookbook on the phone: models that run on the PC, with Ollama or the built-in engine.
struct LocalModelsScreen: View {
    var engine: ModelEngine = .ollama
    var empty = false
    var offline = false
    var setup = false

    @State private var store = LocalModelsStore()
    @State private var search = ""
    @State private var showAll = false
    @State private var showSetup = false
    @State private var deleting: LocalModel?
    @State private var toast: String?
    @State private var started = false

    var body: some View {
        // Paired, the screen shows the desktop's own models and never the sample ones (DeskModelsLive).
        if DeskForgeLive.shared.on {
            DeskModelsScreen(engine: engine, setup: setup)
        } else {
            sampleScreen
        }
    }

    private var sampleScreen: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()
                        GlassSwitch(items: ModelEngine.allCases, selection: $store.engine) { $0.rawValue }
                        Spacer()
                    }
                    .arrives(0)
                    MachineSearchField(prompt: "Search models", text: $search).arrives(1)

                    if store.engine == .ollama && !store.ollamaReachable {
                        unreachable.arrives(2)
                    } else {
                        statusCard.arrives(2)
                        installedSection(proxy).arrives(3)
                    }
                    catalogSection.id("catalog").arrives(4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Local models", subtitle: "Local models on this PC") {
                GlassIconButton(symbol: "questionmark", label: "Setup guide") { showSetup = true }
            }
        }
        .kScreen()
        .machineToast($toast)
        .animation(Motion.snappy, value: store.engine)
        .sheet(isPresented: $showSetup) {
            LocalModelsSetupSheet(store: store)
        }
        .confirmationDialog("Delete this model?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { model in
            Button("Delete \(model.name)", role: .destructive) {
                store.delete(model, from: store.engine)
                toast = "\(model.name) deleted"
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { model in
            Text(deleteMessage(model))
        }
        .onAppear {
            guard !started else { return }
            started = true
            store.engine = engine
            if empty {
                store.ollama = []
                store.builtIn = []
            }
            if offline { store.ollamaReachable = false }
            if setup { showSetup = true }
        }
    }

    private func deleteMessage(_ model: LocalModel) -> String {
        let base = "\(model.name) (\(gb(model.sizeGB))) is removed from your PC. You can download it again later."
        return model.running && store.engine == .builtIn ? base + " It also stops running." : base
    }

    // MARK: Status

    private var unreachable: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.danger)
                Text("Ollama is not reachable").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
            }
            Text("Kairos looks for it at http://localhost:11434 on your PC.")
                .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
            Text("Install Ollama on your PC from ollama.com and open it, then check again. Or use the built-in engine, which needs nothing else.")
                .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
            HStack(spacing: 8) {
                DeskPillButton(title: store.checking ? "Checking..." : "Check again", symbol: "arrow.clockwise") { store.recheck() }
                    .disabled(store.checking)
                DeskPillButton(title: "Use built-in engine", symbol: "cpu") {
                    withAnimation(Motion.snappy) { store.engine = .builtIn }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 22)
    }

    @ViewBuilder
    private var statusCard: some View {
        if store.engine == .ollama {
            ollamaStatus
        } else {
            engineStatus
        }
    }

    private var ollamaStatus: some View {
        let running = store.ollama.filter { $0.running }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PulsingDot(color: Palette.success, size: 8)
                Text("Ollama is running").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text("localhost:11434").font(CodeFont.mono(12.5)).foregroundStyle(Palette.inkFaint)
            }
            if running.isEmpty {
                Text("No model is loaded right now. One loads when a chat uses it.")
                    .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
            } else {
                ForEach(running) { model in
                    HStack(spacing: 8) {
                        Text("RUNNING NOW")
                            .font(KFont.label)
                            .tracking(1.2)
                            .foregroundStyle(Palette.inkFaint)
                        Text("\(model.name) · \(gb(model.sizeGB))")
                            .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(16)
        .kCard(radius: 22, raised: true)
    }

    private var engineStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No separate app to install. Models download straight to your PC and run through a bundled local server.")
                .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
            if let running = store.runningBuiltIn {
                HStack(spacing: 10) {
                    PulsingDot(color: Palette.success, size: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Running: \(running.name)").font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                        Text("http://127.0.0.1:8091").font(CodeFont.mono(12.5)).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer(minLength: 4)
                    DeskPillButton(title: "Stop", symbol: "stop.fill") {
                        store.stopEngine()
                        toast = "\(running.name) stopped"
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Circle().fill(Palette.inkFaint).frame(width: 8, height: 8)
                    Text("No model currently running.").font(KFont.ui(15.5)).foregroundStyle(Palette.inkDim)
                }
            }
        }
        .padding(16)
        .kCard(radius: 22, raised: true)
    }

    // MARK: Installed

    private func installedSection(_ proxy: ScrollViewProxy) -> some View {
        let all = store.installed(store.engine)
        let models = all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Installed").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                Spacer()
                if !all.isEmpty {
                    Text("\(all.count) models · \(gb(store.totalGB(store.engine)))")
                        .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
            }
            if all.isEmpty {
                DeskEmptyNote(
                    symbol: "shippingbox",
                    title: store.engine == .ollama ? "No models installed yet" : "No models downloaded yet",
                    text: store.engine == .ollama ? "Choose a local model from the catalog." : "Choose a model to run on this computer.",
                    action: "Browse catalog"
                ) {
                    withAnimation(Motion.sheet) { proxy.scrollTo("catalog", anchor: .top) }
                }
                .kCard(radius: 22)
            } else if models.isEmpty {
                NoteLine(text: "No installed model matches that.", symbol: "magnifyingglass")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(models.enumerated()), id: \.element.id) { offset, model in
                        modelRow(model, last: offset == models.count - 1)
                    }
                }
                .kCard(radius: 22)
            }
        }
    }

    private func modelRow(_ model: LocalModel, last: Bool) -> some View {
        let builtIn = store.engine == .builtIn
        let chatState = store.chat[model.id]
        return HStack(spacing: 12) {
            Text(String(model.name.prefix(1)).uppercased())
                .font(KFont.ui(18, .semibold))
                .foregroundStyle(Palette.goldText)
                .frame(width: 44, height: 44)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(gb(model.sizeGB)) · \(model.running ? "running" : "installed")")
                        .foregroundStyle(model.running ? Palette.success : Palette.inkFaint)
                    if let chatState {
                        Text(chatState == .adding ? "Adding..." : "Added. See Settings")
                            .foregroundStyle(Palette.goldText)
                            .transition(.opacity)
                    }
                }
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Menu {
                Button {
                    store.useInChat(model)
                } label: {
                    Label(builtIn && !model.running ? "Use in chat (start it first)" : "Use in chat", systemImage: "bubble.left")
                }
                .disabled(chatState != nil || (builtIn && !model.running))
                if builtIn {
                    if model.running {
                        Button {
                            store.stopEngine()
                            toast = "\(model.name) stopped"
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            store.start(model)
                            toast = "\(model.name) started"
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                    }
                }
                Button(role: .destructive) {
                    deleting = model
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(model.name) options")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 70) }
        }
        .animation(Motion.snappy, value: chatState)
    }

    // MARK: Catalog

    private var catalogSection: some View {
        let entries = store.catalog(store.engine).filter {
            search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || $0.about.localizedCaseInsensitiveContains(search)
        }
        let shown = showAll || !search.isEmpty ? entries : Array(entries.prefix(3))
        let more: String? = entries.count > 3 && search.isEmpty ? (showAll ? "Show less" : "Browse all") : nil
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Catalog", action: more) {
                withAnimation(Motion.snappy) { showAll.toggle() }
            }
            Text(store.engine == .ollama ? "A short list we picked, not every model Ollama offers." : "A short list of GGUF models, each checked before it is listed.")
                .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            if shown.isEmpty {
                NoteLine(text: "No catalog model matches that.", symbol: "magnifyingglass")
            }
            ForEach(shown) { entry in
                catalogCard(entry)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func catalogCard(_ entry: CatalogModel) -> some View {
        let state = store.pulls[entry.id]
        let installed = store.isInstalled(entry, store.engine)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.label) (\(entry.params))").font(KFont.ui(16.5, .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text(gb(entry.sizeGB)).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            Text(entry.about).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
            HStack(spacing: 10) {
                switch state {
                case .some(.pulling(let progress)):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(progress == 0 ? "Starting..." : "Pulling \(Int(progress * 100))%")
                            .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                            .foregroundStyle(Palette.goldText)
                            .contentTransition(.numericText())
                        DotProgress(progress: progress)
                    }
                    .frame(minHeight: 44)
                case .some(.failed(let reason)):
                    Text("Failed: \(reason)")
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.danger)
                    Spacer(minLength: 4)
                    DeskPillButton(title: "Retry", symbol: "arrow.clockwise") { store.pull(entry, into: store.engine) }
                case .some(.done), .none:
                    if installed {
                        Chip(text: state == .some(.done) ? "Done. Installed" : "Installed", symbol: "checkmark", filled: true)
                    } else {
                        DeskPillButton(title: "Pull", symbol: "arrow.down", filled: true) { store.pull(entry, into: store.engine) }
                    }
                    Spacer()
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .kCard(radius: 22)
        .animation(Motion.snappy, value: state)
    }

    private func gb(_ value: Double) -> String { String(format: "%.1f GB", value) }
}

// MARK: - Paired: the desktop's own models

/// The Local models screen on live data (DeskModelsLive). Admin accounts only: a member sees one line.
struct DeskModelsScreen: View {
    var setup = false

    @State private var live = DeskModelsLive.shared
    @State private var selected: ModelEngine
    @State private var search = ""
    @State private var showAll = false
    @State private var showSetup = false
    @State private var deleting: DeskModelsInstalled?
    @State private var pulling: DeskModelsEntry?
    @State private var toast: String?
    @State private var notice: String?
    @State private var checking = false
    @State private var started = false

    init(engine: ModelEngine = .ollama, setup: Bool = false) {
        self.setup = setup
        _selected = State(initialValue: engine)
    }

    var body: some View {
        Group {
            if live.isAdmin {
                content
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    DeskForgeLine(text: DeskModelsLive.adminLine)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Local models", subtitle: "Local models on this PC") {
                if live.isAdmin {
                    GlassIconButton(symbol: "questionmark", label: "Setup guide") { showSetup = true }
                }
            }
        }
        .kScreen()
        .machineToast($toast)
        .animation(Motion.snappy, value: selected)
        .onAppear {
            guard !started else { return }
            started = true
            if setup && live.isAdmin { showSetup = true }
        }
        .sheet(isPresented: $showSetup) {
            DeskModelsSetupSheet()
        }
        .sheet(item: $pulling) { entry in
            ConfirmSheet(title: "Download \(entry.title)?", detail: pullDetail(entry), confirm: "Download", danger: false) {
                live.startPull(selected, entry)
            }
        }
        .sheet(item: $deleting) { model in
            ConfirmSheet(title: "Delete \(model.name)?", detail: deleteDetail(model), confirm: "Delete \(model.name)") {
                let engine = selected
                Task { report(await live.delete(engine, model.name), done: "\(model.name) deleted") }
            }
        }
        .task(id: DeskForgeLive.connectionKey + "|" + selected.key) {
            guard live.on, live.isAdmin else { return }
            await live.loadConnections()
            await live.load(selected)
            var rounds = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                rounds += 1
                if live.active(selected) {
                    await live.tick(selected)
                } else if rounds % 5 == 0 {
                    await live.load(selected)
                }
            }
        }
    }

    // MARK: Words

    private func pullDetail(_ entry: DeskModelsEntry) -> String {
        let size: String
        if let rough = DeskModelsWire.estimate(params: entry.params) {
            size = "Your desktop does not list its size. Roughly \(rough), estimated from its \(entry.params) size class."
        } else {
            size = "Your desktop does not list its size, and it can be several GB."
        }
        return "\(entry.title) downloads to your PC. \(size) It uses the PC's disk space and internet connection, and keeps going on the PC if you leave this screen."
    }

    private func deleteDetail(_ model: DeskModelsInstalled) -> String {
        // Ollama models share files between tags, so removing one can free less than its size.
        let frees = selected == .ollama ? "frees up to \(DeskModelsWire.bytes(model.bytes))" : "frees \(DeskModelsWire.bytes(model.bytes))"
        var text = "\(model.name) (\(DeskModelsWire.bytes(model.bytes))) is removed from your PC, which \(frees) of disk space. It cannot be undone from your phone, except by downloading it again."
        if selected == .builtIn && model.running { text += " It also stops running." }
        return text
    }

    private func report(_ outcome: DeskForgeOutcome, done: String) {
        switch outcome {
        case .done:
            Haptics.success()
            toast = done
        case .busy:
            break
        case .refused(let text), .unconfirmed(let text):
            notice = text
        }
    }

    private func reload() {
        Task { await live.load(selected) }
    }

    // MARK: Content

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()
                        GlassSwitch(items: ModelEngine.allCases, selection: $selected) { $0.rawValue }
                        Spacer()
                    }
                    if let notice {
                        DeskForgeLine(text: notice, action: "OK") { self.notice = nil }
                    }
                    MachineSearchField(prompt: "Search models", text: $search)
                    engineBody(proxy)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func engineBody(_ proxy: ScrollViewProxy) -> some View {
        let state = live.state(selected)
        switch state.load {
        case .idle, .loading:
            DeskForgeLine(text: "Reading local models from your desktop.")
        case .failed(let why):
            DeskForgeLine(text: why, action: "Try again") { reload() }
        case .loaded:
            if let stale = state.stale {
                DeskForgeLine(text: stale, action: "Try again") { reload() }
            }
            if selected == .ollama && !state.reachable {
                unreachable
            } else {
                statusCard(state)
                installedSection(state, proxy)
            }
            catalogSection(state)
        }
    }

    // MARK: Status

    private var unreachable: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.danger)
                Text("Ollama is not reachable").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
            }
            Text("Kairos looks for Ollama on your PC and it did not answer.")
                .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
            Text("Install Ollama on your PC from ollama.com and open it, then check again. Or use the built-in engine, which needs nothing else.")
                .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
            HStack(spacing: 8) {
                DeskPillButton(title: checking ? "Checking..." : "Check again", symbol: "arrow.clockwise") {
                    checking = true
                    Task {
                        await live.load(.ollama)
                        checking = false
                    }
                }
                .disabled(checking)
                DeskPillButton(title: "Use built-in engine", symbol: "cpu") {
                    withAnimation(Motion.snappy) { selected = .builtIn }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 22)
    }

    @ViewBuilder
    private func statusCard(_ state: DeskModelsEngineState) -> some View {
        if selected == .ollama {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    PulsingDot(color: Palette.success, size: 8)
                    Text("Ollama is running").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                }
                if state.loaded.isEmpty {
                    Text("No model is loaded right now. One loads when a chat uses it.")
                        .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                } else {
                    ForEach(state.loaded, id: \.name) { model in
                        HStack(spacing: 8) {
                            Text("RUNNING NOW")
                                .font(KFont.label)
                                .tracking(1.2)
                                .foregroundStyle(Palette.inkFaint)
                            Text("\(model.name) · \(DeskModelsWire.bytes(model.bytes)) in memory")
                                .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 22, raised: true)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("No separate app to install. Models download straight to your PC and run through a bundled local server.")
                    .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                if let starting = live.note(DeskModelsLive.engineKey) {
                    HStack(spacing: 10) {
                        ProgressView().tint(Palette.goldText)
                        Text(starting).font(KFont.ui(15, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                    }
                    .frame(minHeight: 44)
                } else if let running = state.runningModel {
                    HStack(spacing: 10) {
                        PulsingDot(color: Palette.success, size: 8)
                        Text("Running: \(running)").font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        DeskPillButton(title: "Stop", symbol: "stop.fill") {
                            Task { report(await live.stopEngine(), done: "\(running) stopped") }
                        }
                        .disabled(live.isBusy(DeskModelsLive.engineKey))
                    }
                } else {
                    HStack(spacing: 10) {
                        Circle().fill(Palette.inkFaint).frame(width: 8, height: 8)
                        Text("No model currently running.").font(KFont.ui(15.5)).foregroundStyle(Palette.inkDim)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 22, raised: true)
        }
    }

    // MARK: Installed

    private func installedSection(_ state: DeskModelsEngineState, _ proxy: ScrollViewProxy) -> some View {
        let all = state.installed
        let models = all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Installed").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink)
                Spacer()
                if !all.isEmpty {
                    Text("\(all.count) models · \(DeskModelsWire.bytes(state.totalBytes))")
                        .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
            }
            if all.isEmpty {
                DeskEmptyNote(
                    symbol: "shippingbox",
                    title: selected == .ollama ? "No models installed yet" : "No models downloaded yet",
                    text: selected == .ollama ? "Choose a local model from the catalog." : "Choose a model to run on this computer.",
                    action: "Browse catalog"
                ) {
                    withAnimation(Motion.sheet) { proxy.scrollTo("catalog", anchor: .top) }
                }
                .kCard(radius: 22)
            } else if models.isEmpty {
                NoteLine(text: "No installed model matches that.", symbol: "magnifyingglass")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(models.enumerated()), id: \.element.name) { offset, model in
                        modelRow(model, last: offset == models.count - 1)
                    }
                }
                .kCard(radius: 22)
            }
            if state.skipped > 0 {
                NoteLine(text: "\(state.skipped) rows from your desktop could not be read and are not shown.", symbol: "exclamationmark.circle")
            }
        }
    }

    private func modelRow(_ model: DeskModelsInstalled, last: Bool) -> some View {
        let builtIn = selected == .builtIn
        let engine = selected
        let inModels = live.connected(engine, model.name)
        let registerHold = live.hold("register", engine, model.name)
        let engineBusy = live.isBusy(DeskModelsLive.engineKey)
        let deleteBusy = live.isBusy("delete|" + DeskModelsLive.progressKey(engine, model.name))
        let canAdd = live.connectionsKnown && !inModels && registerHold == nil && !(builtIn && !model.running)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(String(model.name.prefix(1)).uppercased())
                    .font(KFont.ui(18, .semibold))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 44, height: 44)
                    .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(DeskModelsWire.bytes(model.bytes)) · \(model.running ? "running" : "installed")")
                            .foregroundStyle(model.running ? Palette.success : Palette.inkFaint)
                        if inModels {
                            Text("In your models").foregroundStyle(Palette.goldText)
                        } else if registerHold?.phase == .sending {
                            Text("Adding...").foregroundStyle(Palette.goldText)
                        }
                    }
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                Menu {
                    if inModels {
                        Button {} label: { Label("In your models", systemImage: "checkmark") }
                            .disabled(true)
                    } else {
                        Button {
                            live.startRegister(engine, model.name)
                        } label: {
                            Label(builtIn && !model.running ? "Use in chat (start it first)" : "Use in chat", systemImage: "bubble.left")
                        }
                        .disabled(!canAdd)
                    }
                    if builtIn {
                        if model.running {
                            Button {
                                Task { report(await live.stopEngine(), done: "\(model.name) stopped") }
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .disabled(engineBusy)
                        } else {
                            Button {
                                Task { report(await live.startEngine(model.name), done: "\(model.name) started") }
                            } label: {
                                Label("Start", systemImage: "play.fill")
                            }
                            .disabled(engineBusy || !DeskModelsWire.pathOK(model.name))
                        }
                    }
                    Button(role: .destructive) {
                        deleting = model
                    } label: {
                        Label(DeskModelsWire.pathOK(model.name) ? "Delete" : "Delete (on your desktop)", systemImage: "trash")
                    }
                    .disabled(deleteBusy || !DeskModelsWire.pathOK(model.name))
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("\(model.name) options")
            }
            if !live.connectionsKnown {
                HintLine(text: "Your models list has not been read yet, so Use in chat is off.")
            }
            if let line = live.note(DeskModelsLive.noteKey(engine, model.name)) {
                HintLine(text: line, symbol: "info.circle", color: Palette.goldText)
            }
            holdFooter("register", model.name)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 70) }
        }
    }

    // MARK: Holds

    @ViewBuilder
    private func holdFooter(_ kind: String, _ name: String) -> some View {
        if let line = live.holdLine(kind, selected, name), live.hold(kind, selected, name)?.phase != .sending {
            VStack(alignment: .leading, spacing: 6) {
                HintLine(text: line, symbol: "exclamationmark.triangle", color: Palette.goldText)
                if case .quiet(_)? = live.hold(kind, selected, name)?.phase {
                    HStack(spacing: 8) {
                        DeskPillButton(title: "Check again", symbol: "arrow.clockwise") { live.recheck(kind, selected, name) }
                        DeskPillButton(title: "I checked my desktop") { live.release(kind, selected, name) }
                    }
                }
            }
        }
    }

    // MARK: Catalog

    private func catalogSection(_ state: DeskModelsEngineState) -> some View {
        let entries = state.catalog.filter {
            search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || $0.about.localizedCaseInsensitiveContains(search)
                || $0.name.localizedCaseInsensitiveContains(search)
        }
        let shown = showAll || !search.isEmpty ? entries : Array(entries.prefix(3))
        let more: String? = entries.count > 3 && search.isEmpty ? (showAll ? "Show less" : "Browse all") : nil
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Catalog", action: more) {
                withAnimation(Motion.snappy) { showAll.toggle() }
            }
            .id("catalog")
            Text(selected == .ollama ? "A short list your desktop picked, not every model Ollama offers." : "A short list of GGUF models your desktop checked before listing them.")
                .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            if state.catalog.isEmpty {
                NoteLine(text: "Your desktop sent no catalog.", symbol: "exclamationmark.circle")
            } else if shown.isEmpty {
                NoteLine(text: "No catalog model matches that.", symbol: "magnifyingglass")
            }
            ForEach(shown) { entry in
                catalogCard(entry)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func catalogCard(_ entry: DeskModelsEntry) -> some View {
        let engine = selected
        let progress = live.progress(engine, entry.name)
        let installed = live.isInstalled(engine, entry.name)
        let hold = live.hold("pull", engine, entry.name)
        let verb = engine == .ollama ? "Pull" : "Download"
        return VStack(alignment: .leading, spacing: 8) {
            Text(entry.title).font(KFont.ui(16.5, .semibold)).foregroundStyle(Palette.ink)
            if !entry.about.isEmpty {
                Text(entry.about).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
            }
            HStack(spacing: 10) {
                if installed {
                    Chip(text: "Installed", symbol: "checkmark", filled: true)
                    Spacer()
                } else if hold != nil {
                    Text(hold?.phase == .sending ? "Sending to your desktop..." : "Waiting for your desktop...")
                        .font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(Palette.goldText)
                        .frame(minHeight: 44, alignment: .leading)
                    Spacer()
                } else {
                    switch progress?.phase {
                    case nil:
                        HStack(spacing: 8) {
                            ProgressView().tint(Palette.goldText)
                            Text("Checking your desktop...").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                        .frame(minHeight: 44)
                        Spacer()
                    case .unread?:
                        Text("This one's status could not be read.")
                            .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        Spacer(minLength: 4)
                        DeskPillButton(title: "Check again", symbol: "arrow.clockwise") {
                            Task { await live.recheckProgress(engine, entry.name) }
                        }
                    case .running?:
                        runningView(progress)
                    case .failed?:
                        Text("The \(verb == "Pull" ? "pull" : "download") failed on your desktop. Check its connection and disk space.")
                            .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.danger)
                        Spacer(minLength: 4)
                        DeskPillButton(title: "Try again", symbol: "arrow.clockwise") { pulling = entry }
                    case .done?:
                        if live.finishedMissing(engine, entry.name) {
                            // Nothing was installed (an error inside the pull, or the model was removed outside
                            // Kairos). The button still goes through the confirm, and the phone re-reads first.
                            Text("Your desktop says it finished, but the model is not installed.")
                                .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                            Spacer(minLength: 4)
                            DeskPillButton(title: verb, symbol: "arrow.down", filled: true) { pulling = entry }
                                .disabled(!DeskModelsWire.pathOK(entry.name))
                        } else {
                            Text("Finished. Reading your installed list...")
                                .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                            Spacer()
                        }
                    case .cancelled?, .notStarted?:
                        DeskPillButton(title: verb, symbol: "arrow.down", filled: true) { pulling = entry }
                            .disabled(!DeskModelsWire.pathOK(entry.name))
                        Spacer()
                    }
                }
            }
            .padding(.top, 2)
            if let line = live.note(DeskModelsLive.noteKey(engine, entry.name)) {
                HintLine(text: line, symbol: "info.circle", color: Palette.goldText)
            }
            holdFooter("pull", entry.name)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 22)
        .animation(Motion.snappy, value: progress)
    }

    /// The bar shows only what the desktop's own status says.
    private func runningView(_ progress: DeskModelsProgress?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fraction = progress?.fraction {
                Text("Downloading \(Int(fraction * 100))% · \(DeskModelsWire.bytes(progress?.completed ?? 0)) of \(DeskModelsWire.bytes(progress?.total ?? 0))")
                    .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.goldText)
                    .contentTransition(.numericText())
                DotProgress(progress: fraction)
                if selected == .ollama {
                    Text("Ollama reports each part of a model on its own, so this can start over.")
                        .font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().tint(Palette.goldText)
                    Text("Starting on your desktop...").font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(Palette.goldText)
                }
            }
        }
        .frame(minHeight: 44)
    }
}
