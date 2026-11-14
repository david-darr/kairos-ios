import SwiftUI

/// "Choose how Kairos thinks": the model setup guide, opened from the Cookbook's question mark.
struct LocalModelsSetupSheet: View {
    let store: LocalModelsStore
    var startOnLocal = false

    @State private var showLocal = false
    @State private var glossaryOpen = false
    @State private var started = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose how Kairos thinks")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                if showLocal {
                    recommendation
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    choices
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .kSheet()
        .animation(Motion.snappy, value: showLocal)
        .onAppear {
            guard !started else { return }
            started = true
            showLocal = startOnLocal
        }
    }

    // MARK: Choices

    private var choices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick how your bots and chats get their model. You can change it later in Settings.")
                .font(KFont.ui(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
            ForEach(store.choices) { choice in
                choiceCard(choice)
            }
            DisclosureGroup(isExpanded: $glossaryOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(LocalModelsSample.glossary.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0).font(KFont.ui(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                            Text(item.1).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("What do these words mean?")
                    .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 44)
            }
            .tint(Palette.goldText)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .kCard(radius: 20)
        }
    }

    private func choiceCard(_ choice: SetupChoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(symbol: choice.symbol, size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(choice.title).font(KFont.ui(16.5, .semibold)).foregroundStyle(Palette.ink)
                    Text(choice.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                statusText(choice)
                Spacer(minLength: 4)
                actionButton(choice)
            }
        }
        .padding(14)
        .kCard(radius: 20, raised: choice.state == .ready)
        .animation(Motion.snappy, value: choice.state)
    }

    @ViewBuilder
    private func statusText(_ choice: SetupChoice) -> some View {
        switch choice.state {
        case .ready:
            Label("Set up", systemImage: "checkmark.circle.fill")
                .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.success)
        case .notSet:
            Text("Not set up").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
        case .notInstalled:
            Text("Not installed on your PC").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
        case .waiting:
            HStack(spacing: 6) {
                PulsingDot(color: Palette.working, size: 6)
                Text(choice.id == "key" ? "Paste the key in Settings on your PC" : "Finish signing in on your PC")
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkDim)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ choice: SetupChoice) -> some View {
        switch choice.state {
        case .ready:
            DeskPillButton(title: "Review setup") {
                if choice.id == "local" { showLocal = true } else { store.choose(choice.id) }
            }
        case .waiting:
            DeskPillButton(title: "Cancel waiting") { store.cancelWaiting(choice.id) }
        case .notSet, .notInstalled:
            DeskPillButton(title: "Choose this", filled: true) {
                if choice.id == "local" { showLocal = true } else { store.choose(choice.id) }
            }
        }
    }

    // MARK: Free local model

    private var recommendation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showLocal = false
            } label: {
                Label("Back to choices", systemImage: "chevron.left")
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 44)
            }
            .buttonStyle(PressStyle())

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Recommended for this PC")
                Text("Qwen 3 small (4B)").font(KFont.display(30)).foregroundStyle(Palette.ink)
                Text("About 2.6 GB to download. 118 GB free on your PC.")
                    .font(KFont.ui(15, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                VStack(alignment: .leading, spacing: 6) {
                    bullet("Runs without an account, free and private.")
                    bullet("Good for simple chats. Slower and simpler than paid models.")
                    bullet("Keep Kairos open on your PC while it downloads.")
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 22, raised: true)

            recommendAction
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Palette.gold).frame(width: 5, height: 5)
            Text(text).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
        }
    }

    @ViewBuilder
    private var recommendAction: some View {
        switch store.recommend {
        case .idle:
            GoldButton(title: "Download in the background") {
                withAnimation(Motion.snappy) { store.recommend = .confirming }
            }
        case .confirming:
            VStack(alignment: .leading, spacing: 10) {
                Text("Download about 2.6 GB from huggingface.co to your PC?")
                    .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 10) {
                    DeskPillButton(title: "Not now") {
                        withAnimation(Motion.snappy) { store.recommend = .idle }
                    }
                    DeskPillButton(title: "Download", symbol: "arrow.down", filled: true) { store.downloadRecommended() }
                }
            }
            .padding(14)
            .kCard(radius: 18)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                Text("Downloading in the background... \(Int(progress * 100))%")
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.goldText)
                    .contentTransition(.numericText())
                DotProgress(progress: progress)
                Text("You can close this. The download keeps going on your PC.")
                    .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 18)
        case .starting:
            HStack(spacing: 10) {
                PulsingDot(color: Palette.working, size: 7)
                Text("Starting your local model...").font(KFont.ui(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 18)
        case .connected:
            VStack(alignment: .leading, spacing: 10) {
                Label("Your local model is connected. Chats can use it now.", systemImage: "checkmark.circle.fill")
                    .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.success)
                DeskPillButton(title: "Return to setup") { showLocal = false }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 18)
        }
    }
}

// MARK: - Paired: the desktop's own setup

/// "Choose how Kairos thinks" on live data (DeskModelsLive). Sign-in, keys and installs stay on the desktop: this
/// sheet only says where each choice stands, and downloads, starts and connects the recommended local model.
struct DeskModelsSetupSheet: View {
    @State private var live = DeskModelsLive.shared
    @State private var showLocal = false
    @State private var glossaryOpen = false
    @State private var confirming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose how Kairos thinks")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .kSheet()
        .animation(Motion.snappy, value: showLocal)
        .sheet(isPresented: $confirming) {
            if let rec = live.setup.recommendation {
                ConfirmSheet(title: rec.downloaded ? "Start \(rec.title)?" : "Download \(rec.title)?",
                             detail: confirmDetail(rec), confirm: rec.downloaded ? "Start it" : "Download", danger: false) {
                    live.startSetup()
                }
            }
        }
        .task(id: DeskForgeLive.connectionKey) {
            guard live.on, live.isAdmin else { return }
            await live.loadSetup()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                await live.tickSetup()
            }
        }
    }

    private func confirmDetail(_ rec: DeskModelsRecommendation) -> String {
        if rec.downloaded {
            return "\(rec.title) is already on your PC. This starts it there and adds it to your models. It uses the PC's memory while it runs."
        }
        let size = rec.downloadBytes.map { "About \(DeskModelsWire.bytes($0)) (your desktop's estimate)" } ?? "Your desktop does not say how big it is"
        return "\(size) downloads to your PC, then it starts and is added to your models. It uses the PC's disk space and internet connection, and keeps going on the PC if you close this."
    }

    @ViewBuilder
    private var content: some View {
        let setup = live.setup
        if !live.isAdmin {
            DeskForgeLine(text: DeskModelsLive.adminLine)
        } else {
            switch setup.load {
            case .idle, .loading:
                DeskForgeLine(text: "Reading your desktop's setup.")
            case .failed(let why):
                DeskForgeLine(text: why, action: "Try again") { Task { await live.loadSetup() } }
            case .loaded:
                if showLocal {
                    recommendation(setup)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    choices(setup)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Choices

    private func choices(_ setup: DeskModelsSetupState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick how your bots and chats get their model. You can change it later in Settings.")
                .font(KFont.ui(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
            ForEach(setup.choices) { choice in
                choiceCard(choice)
            }
            DisclosureGroup(isExpanded: $glossaryOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(LocalModelsSample.glossary.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0).font(KFont.ui(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                            Text(item.1).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("What do these words mean?")
                    .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 44)
            }
            .tint(Palette.goldText)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .kCard(radius: 20)
        }
    }

    private func choiceCard(_ choice: SetupChoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(symbol: choice.symbol, size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(choice.title).font(KFont.ui(16.5, .semibold)).foregroundStyle(Palette.ink)
                    Text(choice.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 0)
            }
            if choice.state == .ready {
                HStack(spacing: 8) {
                    Label("Set up", systemImage: "checkmark.circle.fill")
                        .font(KFont.ui(13.5, .medium, relativeTo: .footnote))
                        .foregroundStyle(Palette.success)
                    Spacer(minLength: 4)
                    if choice.id == "local" {
                        DeskPillButton(title: "Review setup") { showLocal = true }
                    }
                }
            } else if choice.id == "local" {
                HStack(spacing: 8) {
                    Text("Not set up").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    Spacer(minLength: 4)
                    DeskPillButton(title: "Choose this", filled: true) { showLocal = true }
                }
            } else {
                // Signing in opens a window on the PC, and keys are typed there: the phone only says where it stands.
                HintLine(text: desktopLine(choice), symbol: "desktopcomputer")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 20, raised: choice.state == .ready)
    }

    private func desktopLine(_ choice: SetupChoice) -> String {
        if choice.id == "key" { return "Not set up. Paste the key in Settings on your desktop." }
        if choice.state == .notInstalled { return "Not installed on your PC. Set it up in Kairos on your desktop." }
        return "Not signed in. Finish signing in on your desktop."
    }

    // MARK: Free local model

    private func recommendation(_ setup: DeskModelsSetupState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showLocal = false
            } label: {
                Label("Back to choices", systemImage: "chevron.left")
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 44)
            }
            .buttonStyle(PressStyle())

            if let rec = setup.recommendation {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Recommended for this PC")
                    Text(rec.title).font(KFont.display(30)).foregroundStyle(Palette.ink)
                    Text(sizeLine(rec))
                        .font(KFont.ui(15, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                    if !rec.about.isEmpty {
                        Text(rec.about).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        bullet("Runs without an account, free and private.")
                        bullet("Good for simple chats. Slower and simpler than paid models.")
                        bullet("Keep Kairos open on your PC while it downloads.")
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(radius: 22, raised: true)

                action(rec, setup)
            } else {
                DeskForgeLine(text: setup.recommendationLine ?? "Your desktop has no recommendation.", action: "Try again") {
                    Task { await live.loadSetup() }
                }
            }
        }
    }

    private func sizeLine(_ rec: DeskModelsRecommendation) -> String {
        var parts: [String] = []
        if rec.downloaded {
            parts.append("Already downloaded on your PC.")
        } else if let bytes = rec.downloadBytes {
            parts.append("About \(DeskModelsWire.bytes(bytes)) to download.")
        }
        if let free = rec.freeBytes { parts.append("\(DeskModelsWire.bytes(free)) free on your PC.") }
        return parts.joined(separator: " ")
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Palette.gold).frame(width: 5, height: 5)
            Text(text).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
        }
    }

    @ViewBuilder
    private func action(_ rec: DeskModelsRecommendation, _ setup: DeskModelsSetupState) -> some View {
        let hold = live.hold("setup", .builtIn, rec.name)
        if let line = live.holdLine("setup", .builtIn, rec.name), hold?.phase != .sending {
            VStack(alignment: .leading, spacing: 8) {
                HintLine(text: line, symbol: "exclamationmark.triangle", color: Palette.goldText)
                if case .quiet(_)? = hold?.phase {
                    HStack(spacing: 8) {
                        DeskPillButton(title: "Check again", symbol: "arrow.clockwise") { live.recheck("setup", .builtIn, rec.name) }
                        DeskPillButton(title: "I checked my desktop") { live.release("setup", .builtIn, rec.name) }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 18)
        } else if hold != nil {
            progressCard("Sending this to your desktop.")
        } else if !setup.stageRead {
            progressCard("Reading where this stands on your desktop.")
        } else {
            switch setup.stage {
            case .idle, .failed:
                VStack(alignment: .leading, spacing: 10) {
                    if setup.stage == .failed {
                        HintLine(text: "Setup stopped on your desktop. Check its connection and disk space, then try again.",
                                 symbol: "exclamationmark.triangle", color: Palette.danger)
                    }
                    if let line = live.note(DeskModelsLive.noteKey(.builtIn, rec.name)) {
                        HintLine(text: line, symbol: "info.circle", color: Palette.goldText)
                    }
                    GoldButton(title: rec.downloaded ? "Start and connect" : "Download in the background") { confirming = true }
                }
            case .preparing:
                progressCard("Getting ready on your desktop.")
            case .downloading(let fraction):
                VStack(alignment: .leading, spacing: 8) {
                    if let fraction {
                        Text("Downloading on your desktop... \(Int(fraction * 100))%")
                            .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.goldText)
                            .contentTransition(.numericText())
                        DotProgress(progress: fraction)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().tint(Palette.goldText)
                            Text("Downloading on your desktop...").font(KFont.ui(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.goldText)
                        }
                    }
                    Text("You can close this. The download keeps going on your PC.")
                        .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(radius: 18)
            case .starting:
                progressCard("Starting your local model on your desktop.")
            case .connected:
                VStack(alignment: .leading, spacing: 10) {
                    Label("Your local model is connected. Chats can use it now.", systemImage: "checkmark.circle.fill")
                        .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.success)
                    DeskPillButton(title: "Return to setup") { showLocal = false }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(radius: 18)
            }
        }
    }

    private func progressCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(Palette.goldText)
            Text(text).font(KFont.ui(15, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 18)
    }
}
