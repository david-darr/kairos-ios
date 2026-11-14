import SwiftUI

/// A sheet title with room under the grab bar.
struct DeskSheetTitle: View {
    let text: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(text)
                .font(KFont.ui(20, .semibold, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
            if let detail {
                Text(detail)
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }
}

/// A row of choices where one is on (gold), as wide as the sheet.
struct ChoiceRow<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var disabled: (Item) -> Bool = { _ in false }
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { selection = item }
                } label: {
                    Text(title(item))
                        .font(KFont.ui(14.5, on ? .semibold : .regular, relativeTo: .subheadline))
                        .foregroundStyle(on ? Palette.onGold : Palette.inkDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if on { Capsule().fill(Palette.gold).matchedGeometryEffect(id: "on", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(disabled(item))
                .opacity(disabled(item) ? 0.4 : 1)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .kCard(radius: 26)
    }
}

// MARK: - Model

nonisolated struct ForgeAgentChoice: Hashable, Sendable {
    var agent: String
    var models: [String]
}

enum ForgeModels {
    static let agents = [
        ForgeAgentChoice(agent: "Claude Code", models: ["Default model", "Claude Opus", "Claude Sonnet", "Claude Haiku"]),
        ForgeAgentChoice(agent: "Codex", models: ["Default model", "GPT-6.1 Sol", "GPT-6.1 Mini"]),
        ForgeAgentChoice(agent: "Antigravity", models: ["Default model", "Gemini Pro", "Gemini Flash"]),
        ForgeAgentChoice(agent: "Qwen local", models: ["CLI default"]),
    ]
    static let efforts = ["Low", "Medium", "High", "Max"]
}

/// Agent, model and effort for a Forge session.
struct ForgeModelSheet: View {
    @Binding var agent: String
    @Binding var model: String
    @Binding var effort: String
    var locked = false
    var onAddModel: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 640) {
            VStack(alignment: .leading, spacing: 16) {
                DeskSheetTitle(text: "Model", detail: locked ? "The agent is fixed once a session starts. You can change the model and effort." : nil)
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Agent")
                    VStack(spacing: 0) {
                        ForEach(Array(ForgeModels.agents.enumerated()), id: \.element.agent) { index, choice in
                            Button {
                                Haptics.select()
                                withAnimation(Motion.snappy) {
                                    agent = choice.agent
                                    if !choice.models.contains(model) { model = choice.models[0] }
                                }
                            } label: {
                                HStack {
                                    Text(choice.agent).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                    Spacer()
                                    if agent == choice.agent {
                                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.goldText)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if index < ForgeModels.agents.count - 1 { Palette.line.frame(height: 1).padding(.leading, 16) }
                                }
                            }
                            .buttonStyle(PressStyle(scale: 0.98))
                            .disabled(locked && agent != choice.agent)
                            .opacity(locked && agent != choice.agent ? 0.4 : 1)
                        }
                    }
                    .kCard(radius: 20)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Model")
                    let models = ForgeModels.agents.first { $0.agent == agent }?.models ?? ["Default model"]
                    FlowChips(items: models, selection: $model)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Effort")
                    ChoiceRow(items: ForgeModels.efforts, selection: $effort, title: { $0 })
                }
                if let onAddModel {
                    Button {
                        dismiss()
                        onAddModel()
                    } label: {
                        CardRow(symbol: "plus.circle", title: "Add a model", detail: "Opens Local models, or connect one on your PC", last: true)
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                    .kCard(radius: 20)
                }
                GoldButton(title: "Done") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

/// Chips that wrap onto more lines; one is selected.
struct FlowChips: View {
    let items: [String]
    @Binding var selection: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { ForEach(items.prefix(2), id: \.self) { chip($0) } }
                HStack(spacing: 8) { ForEach(items.dropFirst(2), id: \.self) { chip($0) } }
            }
        }
    }

    private var chips: some View { ForEach(items, id: \.self) { chip($0) } }

    private func chip(_ item: String) -> some View {
        let on = item == selection
        return Button {
            Haptics.select()
            withAnimation(Motion.snappy) { selection = item }
        } label: {
            Text(item)
                .font(KFont.ui(14.5, on ? .semibold : .regular))
                .foregroundStyle(on ? Palette.onGold : Palette.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.09)), in: Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Full access

/// Supervised or Full access. Full access needs a swipe up.
struct ForgeAccessSheet: View {
    @Binding var access: ForgeAccess
    var startOnConfirm = false
    @State private var confirming = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 520) {
            VStack(spacing: 18) {
                DeskSheetTitle(text: confirming ? "Give full access?" : "Permission mode", detail: confirming ? "The agent will edit files and run commands on your PC without asking. You can switch back at any time." : nil)
                if confirming {
                    VStack(alignment: .leading, spacing: 10) {
                        NoteLine(text: "Works only inside this session's folder or worktree.", symbol: "folder")
                        NoteLine(text: "Pushes, merges and deletes outside it still ask.", symbol: "checkmark.shield")
                    }
                    .padding(16)
                    .kCard(radius: 20)
                    SwipeUpConfirm(title: "Swipe up to give full access", danger: true) {
                        access = .full
                        dismiss()
                    }
                    QuietButton(title: "Cancel") { withAnimation(Motion.snappy) { confirming = false } }
                } else {
                    VStack(spacing: 10) {
                        ForEach(ForgeAccess.allCases, id: \.self) { mode in
                            Button {
                                Haptics.select()
                                if mode == .full && access != .full {
                                    withAnimation(Motion.snappy) { confirming = true }
                                } else {
                                    access = mode
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    IconTile(symbol: mode == .full ? "bolt.shield" : "checkmark.shield", size: 44, tint: mode == .full ? Palette.danger : Palette.goldText)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.rawValue).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                                        Text(mode.explain).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                    }
                                    Spacer()
                                    if access == mode {
                                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.goldText)
                                    }
                                }
                                .padding(14)
                                .kCard(radius: 20, raised: access == mode)
                            }
                            .buttonStyle(PressStyle(scale: 0.98))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear { if startOnConfirm { confirming = true } }
    }
}

// MARK: - End session

struct ForgeEndSheet: View {
    let session: ForgeSessionInfo
    let onEnd: (ForgeEndChoice) -> Void
    @State private var discarding = false
    @State private var merging = false
    @Environment(\.dismiss) private var dismiss

    private var hasChanges: Bool { !session.changes.isEmpty || session.git.ahead > 0 }

    var body: some View {
        FittedSheet(estimate: 560) {
            VStack(spacing: 14) {
                DeskSheetTitle(text: discarding ? "Discard this work?" : (merging ? "Merge back?" : "End session"),
                           detail: discarding ? "The branch and every change in it are deleted. This cannot be undone." :
                            (merging ? "Merges \(session.placeLabel) into main and removes the worktree." : "The conversation is kept either way."))
                if discarding {
                    SwipeUpConfirm(title: "Swipe up to discard", danger: true) { finish(.discard) }
                    QuietButton(title: "Cancel") { withAnimation(Motion.snappy) { discarding = false } }
                } else if merging {
                    SwipeUpConfirm(title: "Swipe up to merge") { finish(.merge) }
                    QuietButton(title: "Cancel") { withAnimation(Motion.snappy) { merging = false } }
                } else {
                    if session.branch == nil {
                        NoteLine(text: "This session works in place. Your folder and its changes stay as they are.", symbol: "folder")
                            .padding(14).kCard(radius: 18)
                    } else if hasChanges {
                        NoteLine(text: "There are \(session.changes.count) changed files that are not merged yet.", symbol: "exclamationmark.triangle")
                            .padding(14).kCard(radius: 18)
                    }
                    VStack(spacing: 0) {
                        if session.branch != nil {
                            choice("arrow.triangle.merge", "Merge back and remove", "Bring the work into main, then tidy up") {
                                withAnimation(Motion.snappy) { merging = true }
                            }
                            choice("arrow.branch", "Keep branch, remove worktree", "The branch stays for later") { finish(.keepBranch) }
                            choice("trash", "Discard", "Delete the branch and its changes", danger: true) {
                                if hasChanges { withAnimation(Motion.snappy) { discarding = true } } else { finish(.discard) }
                            }
                        } else {
                            choice("checkmark.circle", "End session", "Stop the agent and close the session") { finish(.keepBranch) }
                        }
                        choice("arrow.uturn.left", "Keep and leave", "Do not end it now", last: true) { dismiss() }
                    }
                    .kCard(radius: 20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func finish(_ choice: ForgeEndChoice) {
        Haptics.thud()
        dismiss()
        onEnd(choice)
    }

    private func choice(_ symbol: String, _ title: String, _ detail: String, danger: Bool = false, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CardRow(symbol: symbol, title: title, detail: detail, tint: danger ? Palette.danger : Palette.goldText, last: last)
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }
}

// MARK: - Run app

struct ForgeRunAppSheet: View {
    let onRun: (String) -> Void
    @State private var command = "npm run dev -- --port {port}"
    @Environment(\.dismiss) private var dismiss
    private let suggestions = ["npm run dev -- --port {port}", "npm start", "python -m http.server {port}"]

    var body: some View {
        FittedSheet(estimate: 500) {
            VStack(alignment: .leading, spacing: 14) {
                DeskSheetTitle(text: "Run app", detail: "The command runs in this session's folder on your PC.")
                TextField("App command", text: $command)
                    .font(CodeFont.mono(15))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .kCard(radius: 16)
                NoteLine(text: "Use {port} where the port goes. No shell syntax like && or pipes.")
                SectionLabel(text: "Suggested")
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, item in
                        Button { command = item } label: {
                            HStack {
                                Text(item).font(CodeFont.mono(13.5)).foregroundStyle(Palette.ink)
                                Spacer()
                                if command == item { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.goldText) }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 46)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) { if index < suggestions.count - 1 { Palette.line.frame(height: 1) } }
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .kCard(radius: 18)
                GoldButton(title: "Save and run") {
                    dismiss()
                    onRun(command)
                }
                .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(command.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Rename

struct ForgeRenameSheet: View {
    @State var title: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 300) {
            VStack(spacing: 14) {
                DeskSheetTitle(text: "Rename session")
                TextField("Session name", text: $title)
                    .font(KFont.ui(17))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .kCard(radius: 16)
                GoldButton(title: "Save") {
                    let clean = title.trimmingCharacters(in: .whitespaces)
                    guard !clean.isEmpty else { return }
                    dismiss()
                    onSave(clean)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Paired with a desktop

/// The model connections on the paired desktop. One is picked; nothing else is edited here.
/// `onPick` answers a sentence when the pick did not go through, or nil when it did.
struct DeskForgeModelSheet: View {
    let current: String?
    /// The exact version and effort a session has now, shown read only.
    var detail: String? = nil
    /// Picking changes a session on the desktop (and resets its version and effort).
    var changesSession = false
    let onPick: (String) async -> String?

    @State private var live = DeskForgeLive.shared
    @State private var sending: String?
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 520) {
            VStack(alignment: .leading, spacing: 14) {
                DeskSheetTitle(text: "Model", detail: detail)
                if live.models.isEmpty {
                    HintLine(text: "No models were read from your desktop. Add one in Kairos on your desktop.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(live.models.enumerated()), id: \.element.id) { index, choice in
                            Button {
                                pick(choice.id)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(choice.name ?? "Model").font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                                        Text((choice.model ?? "").isEmpty ? "Its own default" : (choice.model ?? ""))
                                            .font(CodeFont.mono(12)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    if sending == choice.id {
                                        ProgressView().tint(Palette.goldText)
                                    } else if current == choice.id {
                                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.goldText)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 54)
                                .contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if index < live.models.count - 1 { Palette.line.frame(height: 1).padding(.leading, 16) }
                                }
                            }
                            .buttonStyle(PressStyle(scale: 0.98))
                        }
                    }
                    .kCard(radius: 20)
                    .disabled(sending != nil)
                }
                if let problem {
                    HintLine(text: problem, symbol: "exclamationmark.triangle", color: Palette.goldText)
                }
                HintLine(text: changesSession
                    ? "Switching uses that connection's own default version and effort. Pick an exact version, set the effort or add a model in Kairos on your desktop."
                    : "Add a model, or pick an exact version and effort, in Kairos on your desktop.")
                GoldButton(title: "Done") { dismiss() }
                    .disabled(sending != nil)
                    .opacity(sending != nil ? 0.5 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .interactiveDismissDisabled(sending != nil)
    }

    private func pick(_ id: String) {
        guard sending == nil else { return }
        guard id != current else {
            dismiss()
            return
        }
        Haptics.select()
        problem = nil
        sending = id
        Task {
            let line = await onPick(id)
            sending = nil
            if let line { problem = line } else { dismiss() }
        }
    }
}

/// A session's permission mode on the paired desktop. This iPhone can switch a session back to Supervised.
/// It never gives Full access.
struct DeskForgeAccessSheet: View {
    let sessionID: String
    @State private var live = DeskForgeLive.shared
    @State private var sending = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let full = live.detail(sessionID)?.fullAccess ?? false
        let running = live.isRunning(sessionID)
        FittedSheet(estimate: 420) {
            VStack(spacing: 16) {
                DeskSheetTitle(text: "Permission mode")
                HStack(spacing: 14) {
                    IconTile(symbol: full ? "bolt.shield" : "checkmark.shield", size: 44, tint: full ? Palette.danger : Palette.goldText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(full ? ForgeAccess.full.rawValue : ForgeAccess.supervised.rawValue)
                            .font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                        Text(full ? ForgeAccess.full.explain : ForgeAccess.supervised.explain)
                            .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .kCard(radius: 20, raised: true)
                if full {
                    PillButton(title: sending ? "Switching..." : "Switch to Supervised", look: .filled, wide: true) {
                        switchBack()
                    }
                    .disabled(sending || running)
                    .opacity(sending || running ? 0.5 : 1)
                    if running { HintLine(text: "Stop the agent first to change the permission mode.") }
                }
                if let problem {
                    HintLine(text: problem, symbol: "exclamationmark.triangle", color: Palette.goldText)
                }
                HintLine(text: "Full access is given in Kairos on your desktop. This iPhone can only switch a session back to Supervised.")
                QuietButton(title: "Close") { dismiss() }
                    .disabled(sending)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .interactiveDismissDisabled(sending)
    }

    private func switchBack() {
        guard !sending else { return }
        Haptics.tap()
        problem = nil
        sending = true
        Task {
            let outcome = await live.setSupervised(sessionID)
            sending = false
            if let line = outcome.line { problem = line } else { dismiss() }
        }
    }
}

/// Rename a session on the paired desktop. Only the name is sent, and only when the person changed it
/// from the name this sheet was filled with.
struct DeskForgeRenameSheet: View {
    let sessionID: String
    @State var title: String
    @State private var filled: String?
    @State private var live = DeskForgeLive.shared
    @State private var sending = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 320) {
            VStack(spacing: 14) {
                DeskSheetTitle(text: "Rename session")
                TextField("Session name", text: $title)
                    .font(KFont.ui(17))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .kCard(radius: 16)
                    .disabled(sending)
                if let problem {
                    HintLine(text: problem, symbol: "exclamationmark.triangle", color: Palette.goldText)
                }
                GoldButton(title: sending ? "Saving..." : "Save") { save() }
                    .disabled(sending)
                    .opacity(sending ? 0.5 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .interactiveDismissDisabled(sending)
        .onAppear { if filled == nil { filled = title } }
    }

    private func save() {
        let clean = title.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !sending else { return }
        // Untouched: nothing is sent, whatever the desktop has now.
        guard clean != (filled ?? "").trimmingCharacters(in: .whitespaces) else {
            dismiss()
            return
        }
        problem = nil
        sending = true
        Task {
            let outcome = await live.rename(sessionID, to: clean)
            sending = false
            if let line = outcome.line { problem = line } else { dismiss() }
        }
    }
}

/// Start the project's saved app command on the paired desktop. The command is read from the desktop when the
/// sheet opens and again every few seconds while it is open, and the button is on only while the desktop still
/// has the very command the person asked about.
struct DeskForgeRunAppSheet: View {
    let projectID: String
    /// The command the person saw when they asked to run the app.
    let command: String
    let onStart: () -> Void

    @State private var live = DeskForgeLive.shared
    /// The saved command as the desktop has it now. nil until read, and again after a read that failed.
    @State private var latest: String?
    @State private var reading = true
    @Environment(\.dismiss) private var dismiss

    private var matches: Bool { latest != nil && latest == command && !command.isEmpty }
    private var changed: Bool { latest != nil && latest != command }

    var body: some View {
        FittedSheet(estimate: 460) {
            VStack(alignment: .leading, spacing: 14) {
                DeskSheetTitle(text: "Start this app?",
                               detail: "It runs in this session's folder on your desktop. A command your desktop has not approved before is shown to you once more.")
                if let latest {
                    SectionLabel(text: "Saved command on your desktop")
                    Text(latest)
                        .font(CodeFont.mono(12.5))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.groundDeep.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if changed {
                    HintLine(text: "The command changed on your desktop. Close this and look again before you start it.",
                             symbol: "exclamationmark.triangle", color: Palette.goldText)
                } else if latest == nil {
                    HintLine(text: reading ? "Reading the saved command from your desktop."
                             : "The saved command could not be read from your desktop, so the app cannot be started from here right now.",
                             symbol: reading ? "clock" : "exclamationmark.triangle", color: reading ? Palette.inkFaint : Palette.goldText)
                }
                PillButton(title: "Start app", look: .filled, wide: true) {
                    guard matches else { return }
                    Haptics.thud()
                    onStart()
                    dismiss()
                }
                .disabled(!matches)
                .opacity(matches ? 1 : 0.45)
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .task {
            while !Task.isCancelled {
                let saved = await live.freshAppCommand(projectID)
                if Task.isCancelled { break }
                latest = saved
                reading = false
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}

/// End a session on the paired desktop. Every way of ending it takes a swipe, and the session only shows as
/// ended once the desktop says so.
struct DeskForgeEndSheet: View {
    nonisolated enum Step: Hashable, Sendable { case choose, merge, keep, discard }

    let sessionID: String
    /// The sentence to show, and whether the session is over (leave its screen).
    let onDone: (String, Bool) -> Void

    @State private var step: Step = .choose
    @State private var sending = false
    @State private var problem: String?
    @State private var live = DeskForgeLive.shared
    @Environment(\.dismiss) private var dismiss

    private var branch: String? { live.detail(sessionID)?.branch }
    private var base: String {
        let name = live.detail(sessionID)?.baseBranch ?? ""
        return name.isEmpty ? "its base branch" : name
    }

    private var titleText: String {
        switch step {
        case .choose: return "End session"
        case .merge: return "Merge back?"
        case .keep: return branch == nil ? "End this session?" : "Remove the worktree?"
        case .discard: return "Discard this work?"
        }
    }

    private var detailText: String {
        switch step {
        case .choose:
            return "The conversation is kept either way."
        case .merge:
            return "Merges \(branch ?? "this branch") into \(base) on your desktop, then removes the worktree. Your desktop asks you to approve the merge."
        case .keep:
            return branch == nil
                ? "The agent and its app stop. Your project folder and its changes stay as they are."
                : "The branch \(branch ?? "") stays for later. Your desktop refuses if the worktree has uncommitted changes."
        case .discard:
            return "The worktree, the branch \(branch ?? "") and every change in it are deleted on your desktop. This cannot be undone."
        }
    }

    var body: some View {
        FittedSheet(estimate: 560) {
            VStack(spacing: 14) {
                DeskSheetTitle(text: titleText, detail: detailText)
                if sending {
                    HStack(spacing: 10) {
                        ProgressView().tint(Palette.goldText)
                        Text("Ending it on your desktop.").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    }
                    .frame(minHeight: 60)
                } else if let problem {
                    HintLine(text: problem, symbol: "exclamationmark.triangle", color: Palette.goldText)
                    QuietButton(title: "Close") { dismiss() }
                } else {
                    switch step {
                    case .merge:
                        SwipeUpConfirm(title: "Swipe up to merge") { merge() }
                        QuietButton(title: "Cancel") { withAnimation(Motion.snappy) { step = .choose } }
                    case .keep:
                        SwipeUpConfirm(title: "Swipe up to end") { finish("keep-branch") }
                        QuietButton(title: "Cancel") { withAnimation(Motion.snappy) { step = .choose } }
                    case .discard:
                        SwipeUpConfirm(title: "Swipe up to discard", danger: true) { finish("discard") }
                        QuietButton(title: "Cancel") { withAnimation(Motion.snappy) { step = .choose } }
                    case .choose:
                        choices
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .interactiveDismissDisabled(sending)
    }

    private var choices: some View {
        VStack(spacing: 0) {
            if branch != nil {
                choice("arrow.triangle.merge", "Merge back and remove", "Bring the work into \(base), then tidy up") {
                    withAnimation(Motion.snappy) { step = .merge }
                }
                choice("arrow.branch", "Keep branch, remove worktree", "The branch stays for later") {
                    withAnimation(Motion.snappy) { step = .keep }
                }
                choice("trash", "Discard", "Delete the branch and its changes", danger: true) {
                    withAnimation(Motion.snappy) { step = .discard }
                }
            } else {
                choice("checkmark.circle", "End session", "Stop the agent and close the session") {
                    withAnimation(Motion.snappy) { step = .keep }
                }
            }
            choice("arrow.uturn.left", "Keep and leave", "Do not end it now", last: true) { dismiss() }
        }
        .kCard(radius: 20)
    }

    private func choice(_ symbol: String, _ title: String, _ detail: String, danger: Bool = false, last: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CardRow(symbol: symbol, title: title, detail: detail, tint: danger ? Palette.danger : Palette.goldText, last: last)
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }

    /// The merge runs over the desktop's approval stream: the session's screen shows the request and the result.
    private func merge() {
        Haptics.thud()
        // Nothing is asked of the desktop while another approval is still waiting on this session.
        guard live.endWithMerge(sessionID) else {
            problem = "Finish the approval that is waiting first."
            return
        }
        dismiss()
        onDone("Asked your desktop to merge. Approve it below.", false)
    }

    private func finish(_ option: String) {
        guard !sending else { return }
        Haptics.thud()
        sending = true
        Task {
            let outcome = await live.end(sessionID, option: option)
            sending = false
            switch outcome {
            case .done:
                dismiss()
                onDone(option == "discard" ? "Discarded on your desktop" : "Session ended", true)
            case .busy:
                dismiss()
            case .refused(let line), .unconfirmed(let line):
                problem = line
            }
        }
    }
}
