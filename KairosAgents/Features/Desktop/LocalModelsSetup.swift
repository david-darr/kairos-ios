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
            PillButton(title: "Review setup") {
                if choice.id == "local" { showLocal = true } else { store.choose(choice.id) }
            }
        case .waiting:
            PillButton(title: "Cancel waiting") { store.cancelWaiting(choice.id) }
        case .notSet, .notInstalled:
            PillButton(title: "Choose this", filled: true) {
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
                    PillButton(title: "Not now") {
                        withAnimation(Motion.snappy) { store.recommend = .idle }
                    }
                    PillButton(title: "Download", symbol: "arrow.down", filled: true) { store.downloadRecommended() }
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
                PillButton(title: "Return to setup") { showLocal = false }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 18)
        }
    }
}
