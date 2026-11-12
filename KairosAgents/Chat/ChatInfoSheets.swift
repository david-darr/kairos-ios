import SwiftUI

// The sheets a model chat opens: its model, its details (context and usage), its background work
// and its summary. Each one reads and changes the chat through `ModelChatState`.

/// One sheet for the chat's model, how hard it thinks, Fast, approval, details and every model.
struct ChatModelSheet: View {
    let chat: ModelChatState
    let openDetails: () -> Void

    @Namespace private var ns
    @State private var options: [ModelOption] = []
    @State private var versions: [ModelVersion] = []
    @State private var details: ChatDetails?
    @State private var confirmFull = false
    @State private var loaded = false

    private var settings: ChatSettings { chat.settings }

    var body: some View {
        FittedSheet(estimate: 690) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Model")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)

                HStack(spacing: 12) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(width: 42, height: 42)
                        .background(Palette.ink.opacity(0.08), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(settings.versionName ?? settings.modelName).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                        Text(settings.source.isEmpty ? "Pick a model below" : settings.source)
                            .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer()
                }
                .padding(14)
                .kCard(radius: 22, raised: true)
                .accessibilityElement(children: .combine)

                if !levels.isEmpty { thinking }

                HStack(spacing: 10) {
                    if let fast = settings.fast {
                        toggleTile(symbol: "bolt.fill", title: "Fast", value: fast ? "On" : "Off", on: fast) {
                            chat.apply { $0.fast = !fast }
                        }
                    }
                    toggleTile(symbol: "checkmark.shield.fill", title: "Approve", value: settings.approval, on: settings.approval == "Full access") {
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

                if versions.count > 1 { versionList }
                modelList
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .task {
            guard !loaded else { return }
            loaded = true
            options = await chat.options()
            if let id = settings.modelID { versions = await chat.versions(of: id) }
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

    /// The levels on offer. A live model also has "Default": send no level at all.
    private var levels: [String?] {
        var efforts = settings.efforts
        if efforts.isEmpty, let version = versions.first(where: { $0.id == settings.versionID }) ?? (versions.count == 1 ? versions.first : nil) {
            efforts = version.efforts
        }
        if efforts.isEmpty { return [] }
        return chat.isSample ? efforts.map { Optional($0) } : [nil] + efforts.map { Optional($0) }
    }

    private var thinking: some View {
        VStack(spacing: 10) {
            SectionLabel(text: "Thinking")
            HStack(spacing: 0) {
                ForEach(levels, id: \.self) { level in
                    let on = level == settings.effort
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) { chat.apply { $0.effort = level; $0.efforts = levels.compactMap { $0 } } }
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

    private var versionList: some View {
        VStack(spacing: 10) {
            SectionLabel(text: "Version")
            VStack(spacing: 0) {
                ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                    row(title: version.name, detail: version.efforts.isEmpty ? "" : "\(version.efforts.count) thinking levels",
                        on: version.id == settings.versionID, last: index == versions.count - 1) {
                        chat.apply {
                            $0.versionID = version.id
                            $0.versionName = version.name
                            $0.efforts = version.efforts
                            if let effort = $0.effort, !version.efforts.contains(effort) { $0.effort = nil }
                        }
                    }
                }
            }
            .kCard(radius: 20)
        }
    }

    private var modelList: some View {
        VStack(spacing: 10) {
            SectionLabel(text: chat.isSample ? "Favourites" : "Your models")
            if options.isEmpty && loaded {
                Text(chat.isSample ? "No models." : "No model is set up on your desktop yet. Add one in Kairos, under Settings, Models.")
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kCard(radius: 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        row(title: option.name, detail: option.source, on: option.id == settings.modelID, last: index == options.count - 1) {
                            guard option.id != settings.modelID else { return }
                            chat.apply {
                                $0.modelID = option.id
                                $0.modelName = option.name
                                $0.source = option.source
                                $0.versionID = nil
                                $0.versionName = nil
                                if !chat.isSample {
                                    $0.effort = nil
                                    $0.efforts = []
                                }
                            }
                            Task { versions = await chat.versions(of: option.id) }
                        }
                    }
                }
                .kCard(radius: 20)
            }
        }
    }

    private func row(title: String, detail: String, on: Bool, last: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { action() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    if !detail.isEmpty {
                        Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                }
                Spacer()
                if on {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.goldText)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { Palette.line.frame(height: 1).padding(.leading, 16) }
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggleTile(symbol: String, title: String, value: String, on: Bool, action: @escaping () -> Void) -> some View {
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
