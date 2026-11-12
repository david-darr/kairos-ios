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
