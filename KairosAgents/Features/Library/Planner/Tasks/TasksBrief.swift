import SwiftUI

/// "Build with Kairos": the Automation brief. Three questions, a model, then a new chat on the desktop
/// builds the automation from the answers.
struct TasksBriefSheet: View {
    let onStart: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var what = ""
    @State private var when = ""
    @State private var deliver = ""
    @State private var model = "Claude Sonnet"
    @State private var missing = false

    private let models = ["Claude Sonnet", "Claude Opus", "GPT-6.1 Sol", "Qwen local"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlannerSheetTitle(title: "Automation brief", subtitle: "Kairos builds it in a new chat")
                Text("Answer three questions. A chat starts on your computer with the brief, and the model builds an automation that runs on its own.")
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)

                PlannerTextField(label: "What should it do?", placeholder: "Describe the inputs and expected output",
                                 text: $what, multiline: true,
                                 error: missing && blank(what) ? "Say what it should do." : nil)
                PlannerTextField(label: "How often or when?", placeholder: "For example, every day at 06:00 local time",
                                 text: $when, error: missing && blank(when) ? "Say how often it runs." : nil)
                PlannerTextField(label: "Where should it deliver?", placeholder: "Tasks tab only, or a configured channel",
                                 text: $deliver, error: missing && blank(deliver) ? "Say where results go." : nil)

                PlannerMenuRow(title: "Model to build it", symbol: "sparkle", options: models, selection: $model,
                               label: { $0 }, last: true)
                    .kCard(radius: 18)

                GoldButton(title: "Start the chat") { start() }
                    .padding(.top, 4)
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .kSheet()
        .animation(Motion.snappy, value: missing)
    }

    private func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func start() {
        guard !blank(what), !blank(when), !blank(deliver) else {
            Haptics.thud()
            missing = true
            return
        }
        Haptics.success()
        onStart("Brief sent to a new chat with \(model)")
        dismiss()
    }
}

/// A short confirmation as a sheet, for deletes: a title, what happens, and one danger button.
struct TasksConfirmSheet: View {
    let title: String
    let message: String
    let button: String
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 300) {
            VStack(spacing: 14) {
                PlannerSheetTitle(title: title)
                Text(message)
                    .font(KFont.ui(15.5))
                    .foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                PlannerPill(title: button, symbol: "trash", style: .danger, expand: true) {
                    Haptics.thud()
                    action()
                    dismiss()
                }
                .padding(.top, 6)
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}
