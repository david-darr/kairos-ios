import SwiftUI

// The sheets a model chat opens: its model, its details (context and usage), its background work
// and its summary. Each one reads and changes the chat through `ModelChatState`.

/// One sheet for the chat's model, how hard it thinks, Fast, approval, details and every model.
struct ChatModelSheet: View {
    let chat: ModelChatState
    let openDetails: () -> Void

    @Namespace private var ns
    @State private var options: [ModelOption] = []
    @State private var details: ChatDetails?
    @State private var confirmFull = false
    @State private var loaded = false

    private var settings: ChatSettings { chat.settings }

    var body: some View {
        FittedSheet(estimate: 720) {
            VStack(alignment: .leading, spacing: 18) {
                ModelSheetTitle()
                CurrentModelCard(settings: settings, note: nil)

                if !settings.efforts.isEmpty {
                    ThinkingPicker(settings: settings, offersDefault: !chat.isSample, ns: ns) { level in
                        chat.apply { $0.effort = level }
                    }
                }

                HStack(spacing: 10) {
                    if let fast = settings.fast {
                        ModelToggleTile(symbol: "bolt.fill", title: "Fast", value: fast ? "On" : "Off", on: fast) {
                            chat.apply { $0.fast = !fast }
                        }
                    }
                    ModelToggleTile(symbol: "checkmark.shield.fill", title: "Approve", value: settings.approval, on: settings.approval == "Full access") {
                        cycleApproval()
                    }
                }

                Button(action: openDetails) {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Details").font(KFont.ui(15.5, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(contextLine).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                        }
                        ContextBar(details: details)
                    }
                    .padding(14)
                    .kCard(radius: 20)
                }
                .buttonStyle(PressStyle(scale: 0.985))
                .accessibilityLabel("Chat details: \(contextLine)")

                ModelPickerList(
                    settings: settings, options: options, loaded: loaded,
                    title: chat.isSample ? "Models" : "Your models",
                    versions: { await chat.versions(of: $0) }
                ) { option, version in
                    chat.apply { ModelPickerList.pick(option, version, into: &$0) }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .task {
            guard !loaded else { return }
            options = await chat.options()
            loaded = true
            details = try? await chat.details()
        }
        .confirmationDialog("Give this chat full access?", isPresented: $confirmFull, titleVisibility: .visible) {
            Button("Give full access", role: .destructive) {
                Haptics.thud()
                chat.apply { $0.approval = "Full access" }
            }
            Button("Keep asking first", role: .cancel) {}
        } message: {
            Text("The model will act on your desktop without asking, also after reading outside content. You can switch back at any time.")
        }
    }

    private var contextLine: String {
        guard let details, let used = details.usedTokens else { return "Context and usage" }
        if let window = details.windowTokens { return "\(ChatDetails.tokens(used)) of \(ChatDetails.tokens(window))" }
        return "\(ChatDetails.tokens(used)) used"
    }

    private func cycleApproval() {
        let all = settings.approvals
        guard all.count > 1 else {
            chat.notice = "Only an admin of the desktop can give a chat full access."
            return
        }
        let index = all.firstIndex(of: settings.approval) ?? 0
        let next = all[(index + 1) % all.count]
        if next == "Full access" {
            confirmFull = true
        } else {
            chat.apply { $0.approval = next }
        }
    }
}

/// The same drawer for one bot conversation: its model and how hard it thinks, or the bot's own model.
struct BotModelSheet: View {
    let chat: BotChatState

    @Namespace private var ns
    @State private var options: [ModelOption] = []
    @State private var loaded = false
    @State private var switching: (option: ModelOption, version: ModelVersion?)?

    var body: some View {
        FittedSheet(estimate: 640) {
            VStack(alignment: .leading, spacing: 18) {
                ModelSheetTitle()
                if let settings = chat.model {
                    CurrentModelCard(settings: settings, note: settings.followsBot == true ? "Follows \(chat.bot.name)'s model" : "Chosen for this conversation")

                    if !settings.efforts.isEmpty {
                        ThinkingPicker(settings: settings, offersDefault: !chat.isSample, ns: ns) { level in
                            chat.applyModel { $0.effort = level }
                        }
                    }

                    if settings.followsBot == false {
                        Button {
                            Haptics.select()
                            chat.applyModel { $0 = ChatSettings(approvals: [], followsBot: true) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                    .frame(width: 34, height: 34)
                                    .background(Palette.ink.opacity(0.1), in: Circle())
                                Text("Follow \(chat.bot.name)'s model")
                                    .font(KFont.ui(15.5, .medium, relativeTo: .subheadline))
                                    .foregroundStyle(Palette.ink)
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .kCard(radius: 20)
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                    }

                    ModelPickerList(
                        settings: settings, options: options, loaded: loaded, title: "Models",
                        versions: { await chat.versions(of: $0) }
                    ) { option, version in
                        if let current = options.first(where: { $0.id == settings.modelID }), current.source != option.source, !chat.isSample {
                            switching = (option, version)
                        } else {
                            chat.applyModel { ModelPickerList.pick(option, version, into: &$0) }
                        }
                    }
                } else {
                    ProgressView()
                        .tint(Palette.inkDim)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .task {
            guard !loaded else { return }
            async let read: Void = chat.loadModel()
            options = await chat.options()
            await read
            loaded = true
        }
        .confirmationDialog("Switch model families?", isPresented: switchingShown, titleVisibility: .visible) {
            Button("Switch model") {
                guard let pick = switching else { return }
                switching = nil
                chat.applyModel { ModelPickerList.pick(pick.option, pick.version, into: &$0) }
            }
            Button("Cancel", role: .cancel) { switching = nil }
        } message: {
            Text("This conversation will continue with a different model family using its saved transcript.")
        }
    }

    private var switchingShown: Binding<Bool> {
        Binding(get: { switching != nil }, set: { if !$0 { switching = nil } })
    }
}

private struct ModelSheetTitle: View {
    var body: some View {
        Text("Model")
            .font(KFont.ui(20, .semibold, relativeTo: .title3))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
    }
}

private struct CurrentModelCard: View {
    let settings: ChatSettings
    let note: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 42, height: 42)
                .background(Palette.ink.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(settings.versionName ?? settings.modelName).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                Text(line).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            Spacer()
        }
        .padding(14)
        .kCard(radius: 22, raised: true)
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        let source = settings.source.isEmpty ? "Pick a model below" : settings.source
        guard let note else { return source }
        return settings.source.isEmpty ? note : "\(source) · \(note)"
    }
}

/// How hard the model thinks. A live model also has "Default": send no level at all.
private struct ThinkingPicker: View {
    let settings: ChatSettings
    let offersDefault: Bool
    let ns: Namespace.ID
    let choose: (String?) -> Void

    private var levels: [String?] { (offersDefault ? [nil] : []) + settings.efforts.map { Optional($0) } }

    var body: some View {
        VStack(spacing: 10) {
            SectionLabel(text: "Thinking")
            HStack(spacing: 0) {
                ForEach(levels, id: \.self) { level in
                    let on = level == settings.effort
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) { choose(level) }
                    } label: {
                        Text(level.map(ChatSettings.effortWord) ?? "Default")
                            .font(KFont.ui(14.5, on ? .semibold : .regular, relativeTo: .subheadline))
                            .foregroundStyle(on ? Palette.onGold : Palette.inkDim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background {
                                if on { Capsule().fill(Palette.gold).matchedGeometryEffect(id: "level", in: ns) }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(4)
            .kCard(radius: 26)
        }
    }
}

private struct ModelToggleTile: View {
    let symbol: String
    let title: String
    let value: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(on ? Palette.onGold : Palette.ink)
                    .frame(width: 34, height: 34)
                    .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(KFont.ui(15.5, .medium, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                    Text(value)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(on ? Palette.goldText : Palette.inkFaint)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .kCard(radius: 20, raised: on)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(title): \(value)")
    }
}

/// Every connection (Claude, Codex, a local model...), each opening to its own models.
/// A connection without a list of models is picked as it is.
struct ModelPickerList: View {
    let settings: ChatSettings
    let options: [ModelOption]
    let loaded: Bool
    let title: String
    let versions: (String) async -> [ModelVersion]
    let choose: (ModelOption, ModelVersion?) -> Void

    @State private var open: Set<String> = []
    @State private var catalog: [String: [ModelVersion]] = [:]
    @State private var loading: Set<String> = []
    @State private var started = false

    /// Put a picked connection and model into the settings; a level the new model lacks is dropped.
    static func pick(_ option: ModelOption, _ version: ModelVersion?, into settings: inout ChatSettings) {
        settings.modelID = option.id
        settings.modelName = option.name
        settings.source = option.source
        settings.versionID = version?.id
        settings.versionName = version?.name
        settings.efforts = version?.efforts ?? []
        if let effort = settings.effort, !settings.efforts.contains(effort) { settings.effort = nil }
    }

    var body: some View {
        VStack(spacing: 10) {
            SectionLabel(text: title)
            if options.isEmpty && loaded {
                Text("No model is set up on your desktop yet. Add one in Kairos, under Settings, Models.")
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kCard(radius: 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        connection(option, last: index == options.count - 1)
                    }
                }
                .kCard(radius: 20)
            }
        }
        .onChange(of: options) { openCurrent() }
        .onAppear { openCurrent() }
    }

    /// The connection in use starts open, so its models show at once.
    private func openCurrent() {
        guard !started, let id = settings.modelID, options.contains(where: { $0.id == id }) else { return }
        started = true
        open.insert(id)
        Task { await read(id) }
    }

    private func read(_ id: String) async {
        guard catalog[id] == nil, !loading.contains(id) else { return }
        loading.insert(id)
        let list = await versions(id)
        loading.remove(id)
        catalog[id] = list
    }

    @ViewBuilder
    private func connection(_ option: ModelOption, last: Bool) -> some View {
        let isOpen = open.contains(option.id)
        let models = catalog[option.id]
        let inUse = option.id == settings.modelID
        Button {
            Haptics.select()
            if let models, models.isEmpty {
                // Nothing to open: the connection is the model.
                withAnimation(Motion.snappy) { choose(option, nil) }
                return
            }
            withAnimation(Motion.snappy) {
                if isOpen { open.remove(option.id) } else { open.insert(option.id) }
            }
            Task { await read(option.id) }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.name).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                    Text(subtitle(option, models: models, inUse: inUse))
                        .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }
                Spacer()
                if loading.contains(option.id) {
                    ProgressView().tint(Palette.inkDim).controlSize(.small)
                } else if let models, models.isEmpty {
                    if inUse {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.goldText)
                    }
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(inUse ? Palette.goldText : Palette.inkFaint)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last || isOpen { Palette.line.frame(height: 1).padding(.leading, 16) }
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .accessibilityLabel("\(option.name), \(option.source)")
        .accessibilityHint(isOpen ? "Hides its models" : "Shows its models")

        if isOpen, let models, !models.isEmpty {
            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                let on = inUse && model.id == settings.versionID
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { choose(option, model) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.name).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                            if !model.efforts.isEmpty {
                                Text("\(model.efforts.count) thinking levels")
                                    .font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                            }
                        }
                        Spacer()
                        if on {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.goldText)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.leading, 32)
                    .padding(.trailing, 16)
                    .frame(minHeight: 50)
                    .background(Palette.ink.opacity(0.03))
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if !(last && index == models.count - 1) { Palette.line.frame(height: 1).padding(.leading, 32) }
                    }
                }
                .buttonStyle(PressStyle(scale: 0.99))
                .accessibilityAddTraits(on ? .isSelected : [])
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func subtitle(_ option: ModelOption, models: [ModelVersion]?, inUse: Bool) -> String {
        if inUse, let name = settings.versionName { return "\(option.source) · \(name)" }
        if let models, !models.isEmpty { return "\(option.source) · \(models.count) models" }
        return option.source
    }
}

/// The context window as one bar, split by what fills it.
struct ContextBar: View {
    let details: ChatDetails?

    static let tints: [Color] = [Palette.inkFaint, Color(hex: Palette.botSand), Color(hex: Palette.botSage), Palette.working, Color(hex: Palette.botLilac), Color(hex: Palette.botRose)]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.1))
                if let details, let window = details.windowTokens, window > 0 {
                    HStack(spacing: 2) {
                        if details.parts.isEmpty, let used = details.usedTokens {
                            Capsule().fill(Palette.working).frame(width: max(3, geometry.size.width * CGFloat(used) / CGFloat(window)))
                        }
                        ForEach(Array(details.parts.enumerated()), id: \.element.id) { index, part in
                            Capsule()
                                .fill(ContextBar.tints[index % ContextBar.tints.count])
                                .frame(width: max(3, geometry.size.width * CGFloat(part.tokens) / CGFloat(window)))
                        }
                    }
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// "Chat details": how full the context window is and what the chat has used.
struct ChatDetailsSheet: View {
    let chat: ModelChatState
    @Environment(\.dismiss) private var dismiss
    @State private var details: ChatDetails?
    @State private var problem: String?
    @State private var compacting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    Text("Chat details")
                        .font(KFont.ui(20, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                    HStack {
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(KFont.ui(16, .medium))
                            .foregroundStyle(Palette.goldText)
                            .frame(minWidth: 56, minHeight: 44)
                    }
                }
                .padding(.top, 26)

                if let details {
                    context(details)
                    usage(details)
                    if let note = details.note {
                        Text(note)
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        compacting = true
                        Task {
                            let done = await chat.compact()
                            compacting = false
                            if done {
                                chat.notice = "Chat compacted. The full conversation is still above."
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if compacting { ProgressView().tint(Palette.ink) }
                            Text(compacting ? "Compacting" : "Compact this chat")
                                .font(KFont.ui(16, .medium))
                        }
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Palette.ink.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                    .disabled(compacting || chat.isBusy)
                    .accessibilityHint("Summarises older turns so later messages send less. Nothing is deleted.")
                    Text("Source: this chat's recorded runs, as each provider reported them. n/a means not reported.")
                        .font(KFont.ui(12.5, relativeTo: .caption))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let problem {
                    Text(problem)
                        .font(KFont.ui(15.5))
                        .foregroundStyle(Palette.inkDim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().tint(Palette.gold)
                        Text("Reading this chat's usage").font(KFont.ui(15.5)).foregroundStyle(Palette.inkDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 50)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .kSheet()
        .task {
            do {
                details = try await chat.details()
            } catch {
                problem = "Usage could not be read for this chat. " + error.plainWords
            }
        }
    }

    private func context(_ details: ChatDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Context")
            if let used = details.usedTokens {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ChatDetails.tokens(used)).font(KFont.ui(26, .semibold, relativeTo: .title2)).foregroundStyle(Palette.ink)
                    if let window = details.windowTokens {
                        Text("of \(ChatDetails.tokens(window))").font(KFont.ui(15, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                    }
                    Spacer()
                    if let percent = details.percent {
                        Text("\(Int(percent.rounded()))%")
                            .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(percent >= 90 ? Palette.danger : (percent >= 70 ? Palette.goldText : Palette.inkDim))
                    }
                }
                ContextBar(details: details)
                if !details.parts.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(details.parts.enumerated()), id: \.element.id) { index, part in
                            HStack(spacing: 8) {
                                Circle().fill(ContextBar.tints[index % ContextBar.tints.count]).frame(width: 8, height: 8)
                                Text(part.label).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.ink)
                                Spacer()
                                Text((part.estimated ? "~" : "") + ChatDetails.tokens(part.tokens))
                                    .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).monospacedDigit()
                            }
                        }
                    }
                }
                Text(details.windowEstimated ? "Window size estimated." : "Window size reported by the provider.")
                    .font(KFont.ui(12.5, relativeTo: .caption))
                    .foregroundStyle(Palette.inkFaint)
            } else {
                Text("No context reading for this chat yet.")
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 20)
    }

    private func usage(_ details: ChatDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Model and usage").padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(details.rows.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text(row.id).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                        Spacer(minLength: 12)
                        Text(row.value)
                            .font(KFont.ui(15))
                            .foregroundStyle(row.value == "n/a" ? Palette.inkFaint : Palette.inkDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottom) {
                        if index < details.rows.count - 1 { Palette.line.frame(height: 1).padding(.leading, 16) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .kCard(radius: 20)
        }
    }
}

/// "In the background": work that keeps going behind a chat.
struct BackgroundSheet: View {
    let items: [BackgroundItem]

    var body: some View {
        FittedSheet(estimate: 420) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 3) {
                    Text("In the background")
                        .font(KFont.ui(20, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                    Text(counts)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 30)

                if items.isEmpty {
                    Text("Nothing is running behind this chat.")
                        .font(KFont.ui(15.5))
                        .foregroundStyle(Palette.inkDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Group {
                            if item.isRunning {
                                PulsingDot(color: Palette.working, size: 8)
                            } else {
                                Image(systemName: item.status == "failed" ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(item.status == "failed" ? Palette.danger : Palette.success)
                            }
                        }
                        .frame(width: 18, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                            Text("\(item.kindWord) · \(item.statusWord)" + (elapsed(item).isEmpty ? "" : " · \(elapsed(item))"))
                                .font(KFont.ui(13, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkFaint)
                            if !item.activity.isEmpty {
                                Text(item.activity).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kCard(radius: 18, raised: item.isRunning)
                    .arrives(index)
                    .accessibilityElement(children: .combine)
                }
                Text("This work keeps going if you leave the chat.")
                    .font(KFont.ui(12.5, relativeTo: .caption))
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private var counts: String {
        let running = items.filter { $0.status == "running" || $0.status == "queued" }.count
        let waiting = items.filter { $0.status == "waiting" }.count
        let done = items.filter { !$0.isRunning }.count
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if waiting > 0 { parts.append("\(waiting) waiting on you") }
        if done > 0 { parts.append("\(done) done") }
        return parts.isEmpty ? "Nothing right now" : parts.joined(separator: " · ")
    }

    private func elapsed(_ item: BackgroundItem) -> String {
        guard let start = item.startedAt else { return "" }
        let seconds = Int((item.endedAt ?? Date()).timeIntervalSince(start))
        if seconds < 0 { return "" }
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
    }
}

/// "Chat summary": what the chat has covered, made on the desktop.
struct ChatSummarySheet: View {
    let chat: ModelChatState
    @State private var text: String?
    @State private var problem: String?
    @State private var working = true

    var body: some View {
        FittedSheet(estimate: 380) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Chat summary")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                if working {
                    HStack(spacing: 10) {
                        ProgressView().tint(Palette.gold)
                        Text("Writing the summary").font(KFont.ui(15.5)).foregroundStyle(Palette.inkDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else if let text {
                    MarkdownText(text: text, size: 16)
                        .padding(14)
                        .kCard(radius: 20)
                    QuietButton(title: "Update summary") { load(refresh: true) }
                } else {
                    Text(problem ?? "The summary could not be made.")
                        .font(KFont.ui(15.5))
                        .foregroundStyle(Palette.inkDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    QuietButton(title: "Try again") { load(refresh: false) }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .task { if text == nil { load(refresh: false) } }
    }

    private func load(refresh: Bool) {
        working = true
        Task {
            do {
                text = try await chat.summary(refresh: refresh)
                problem = nil
            } catch {
                text = nil
                problem = error.plainWords
            }
            working = false
        }
    }
}
