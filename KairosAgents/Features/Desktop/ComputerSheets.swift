import SwiftUI

/// The steps Kairos took on the computer, one at a time, with the kept pictures.
struct ComputerStepsSheet: View {
    let runs: [ComputerRun]
    let onSkill: () -> Void

    @State private var runID: String?
    @State private var index = 0
    @State private var shot: ComputerShot = .after

    private var run: ComputerRun? {
        if let runID { return runs.first { $0.id == runID } }
        return runs.count == 1 ? runs.first : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Steps")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                if runs.isEmpty {
                    EmptyNote(symbol: "list.number", title: "No steps yet", text: "No computer steps are kept for this computer yet.")
                } else if let run {
                    viewer(run)
                } else {
                    chooser
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kSheet()
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Choose a run")
            VStack(spacing: 0) {
                ForEach(Array(runs.enumerated()), id: \.element.id) { offset, item in
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) {
                            runID = item.id
                            index = 0
                            shot = .after
                        }
                    } label: {
                        CardRow(symbol: "play.rectangle", title: item.when, detail: "\(item.steps.count) steps", last: offset == runs.count - 1)
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }
            .kCard(radius: 20)
        }
    }

    private func viewer(_ run: ComputerRun) -> some View {
        let step = run.steps[min(index, run.steps.count - 1)]
        let before = index > 0 ? run.steps[index - 1].typed : ""
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                if runs.count > 1 {
                    Button {
                        withAnimation(Motion.snappy) { runID = nil }
                    } label: {
                        Label("All runs", systemImage: "chevron.left")
                            .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.goldText)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(PressStyle())
                }
                Spacer()
                Text("Step \(index + 1) of \(run.steps.count)")
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .contentTransition(.numericText())
            }

            Group {
                if let missing = step.missing, shot != .click {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash").font(.system(size: 22, weight: .medium)).foregroundStyle(Palette.inkFaint)
                        Text(missing).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .kCard(radius: 14)
                } else if shot == .click && step.point == nil {
                    Text("This step was not a click, so there is no click picture.")
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .multilineTextAlignment(.center)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .kCard(radius: 14)
                } else {
                    ComputerFrame(typed: shot == .before ? before : step.typed, marker: shot == .click ? step.point : nil)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                }
            }
            .id("\(run.id)-\(index)-\(shot.rawValue)")
            .transition(.opacity)

            HStack {
                Spacer()
                GlassSwitch(items: ComputerShot.allCases, selection: $shot) { $0.rawValue }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(step.action.prefix(1)).uppercased() + String(step.action.dropFirst()))
                    .font(KFont.ui(17, .medium))
                    .foregroundStyle(Palette.ink)
                Text(step.result)
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(step.failed ? Palette.danger : Palette.inkDim)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 18)

            HStack(spacing: 10) {
                PillButton(title: "Previous", symbol: "chevron.left") {
                    withAnimation(Motion.snappy) { index = max(0, index - 1) }
                }
                .disabled(index == 0)
                .opacity(index == 0 ? 0.4 : 1)
                Spacer()
                PillButton(title: "Next", symbol: "chevron.right") {
                    withAnimation(Motion.snappy) { index = min(run.steps.count - 1, index + 1) }
                }
                .disabled(index >= run.steps.count - 1)
                .opacity(index >= run.steps.count - 1 ? 0.4 : 1)
            }

            HStack(spacing: 10) {
                ShareLink(item: summary(run), preview: SharePreview("Computer steps, \(run.when)")) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Palette.ink.opacity(0.1), in: Capsule())
                }
                PillButton(title: "Make a skill", symbol: "wand.and.stars", filled: true) { onSkill() }
            }
            NoteLine(text: "Export shares the steps as text. The full export with pictures is on your PC.")
        }
    }

    private func summary(_ run: ComputerRun) -> String {
        var lines = ["Computer steps, \(run.when)"]
        for (offset, step) in run.steps.enumerated() {
            lines.append("\(offset + 1). \(step.action): \(step.result)")
        }
        return lines.joined(separator: "\n")
    }
}

/// After a recording: name it and keep it as a skill, or let it go.
struct ComputerSkillReview: View {
    let steps: Int
    let done: (Bool) -> Void
    @State private var name = "Write an order note"

    var body: some View {
        FittedSheet(estimate: 420) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Make a skill")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                Text("Kairos turns these \(steps) steps into a skill your bots can run again. Check it on your PC before a bot uses it.")
                    .font(KFont.ui(15.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Name")
                    TextField("Skill name", text: $name)
                        .font(KFont.ui(16.5))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .kCard(radius: 16)
                }
                GoldButton(title: "Save as a skill") {
                    Haptics.success()
                    done(true)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                QuietButton(title: "Discard") { done(false) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}
