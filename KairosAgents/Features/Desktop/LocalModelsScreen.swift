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
                PillButton(title: store.checking ? "Checking..." : "Check again", symbol: "arrow.clockwise") { store.recheck() }
                    .disabled(store.checking)
                PillButton(title: "Use built-in engine", symbol: "cpu") {
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
                    PillButton(title: "Stop", symbol: "stop.fill") {
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
                EmptyNote(
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
                    PillButton(title: "Retry", symbol: "arrow.clockwise") { store.pull(entry, into: store.engine) }
                case .some(.done), .none:
                    if installed {
                        Chip(text: state == .some(.done) ? "Done. Installed" : "Installed", symbol: "checkmark", filled: true)
                    } else {
                        PillButton(title: "Pull", symbol: "arrow.down", filled: true) { store.pull(entry, into: store.engine) }
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
