import SwiftUI

/// Edit a Google Form: its title, its questions, whether it takes responses, and what came back.
struct DriveFormEditor: View {
    let fileID: String
    @Environment(DriveUI.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var questionText = ""
    @State private var type: DriveQuestionType = .short
    @State private var choicesText = ""
    @State private var removing: DriveQuestion?
    @State private var responses: [String]?
    @State private var started = false
    // Paired: the form as last read, the title it was filled from, and a change on its way.
    @State private var liveRead: DriveDTOForm?
    @State private var liveLoad: DriveLiveLoad = .idle
    @State private var titleBase = ""
    @State private var liveNote: String?
    @State private var moreResponses = false

    private var file: DriveFile? { ui.store.file(fileID) }
    private var form: DriveForm? {
        if ui.live { return liveRead.map(DriveStore.liveForm) }
        return file?.form
    }
    private var working: Bool { ui.live && ui.store.busy.contains(fileID) }

    var body: some View {
        ScrollView {
            if let form {
                VStack(alignment: .leading, spacing: 18) {
                    if ui.live, let liveNote {
                        DriveLiveLine(text: liveNote, action: "OK") { self.liveNote = nil }
                    }
                    if working {
                        HintLine(text: "Sending to your desktop.", symbol: "hourglass")
                    }
                    titleCard.arrives(0)
                    questions(form).arrives(1)
                    newQuestion.arrives(2)
                    publishing(form).arrives(3)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            } else if ui.live, case .failed(let why) = liveLoad {
                DriveLiveLine(text: why, action: "Try again") { Task { await loadLive() } }
                    .padding(.horizontal, 16)
            } else if ui.live {
                DriveLiveLine(text: "Reading the form.")
                    .padding(.horizontal, 16)
            } else {
                FilesEmpty(symbol: "list.bullet.rectangle", title: "This form is gone", detail: "It was deleted or moved out of this Drive.", action: "Go back") { dismiss() }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            FilesHeader(title: file?.name ?? "Form", subtitle: "Forms editor", back: { dismiss() })
        }
        .kScreen()
        .onAppear {
            guard !started else { return }
            started = true
            title = form?.title ?? ""
        }
        .task(id: DriveStore.connectionKey) { await loadLive() }
        .confirmationDialog(
            "Remove question?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { question in
            Button("Remove", role: .destructive) {
                withAnimation(Motion.snappy) { ui.store.removeQuestion(fileID, question: question.id) }
                Haptics.thud()
                ui.toaster.say("Question removed")
            }
            Button("Cancel", role: .cancel) {}
        } message: { question in
            Text("\"\(question.text)\" and its answers leave the form.")
        }
    }

    // MARK: Title

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Form title")
            HStack(spacing: 10) {
                field("Form title", text: $title)
                pillButton("Save title") {
                    let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else {
                        ui.toaster.say("Give the form a title")
                        return
                    }
                    if ui.live {
                        saveTitleLive(clean)
                        return
                    }
                    ui.store.setFormTitle(fileID, clean)
                    Haptics.success()
                    ui.toaster.say("Form title saved")
                }
            }
        }
    }

    // MARK: Questions

    private func questions(_ form: DriveForm) -> some View {
        FilesGroup(label: "Questions") {
            if form.questions.isEmpty {
                Text("No questions yet. Add one below.")
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kCard(radius: 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(form.questions.enumerated()), id: \.element.id) { index, question in
                        questionRow(question, number: index + 1, last: index == form.questions.count - 1)
                    }
                }
                .kCard(radius: 18)
                if ui.live {
                    // Google removes a question by its position, and the desktop cannot send Google's revision
                    // guard: a change in between could remove a different question and its answers.
                    HintLine(text: "Remove questions in Google Forms.", symbol: "info.circle")
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func questionRow(_ question: DriveQuestion, number: Int, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(KFont.ui(14, .semibold, relativeTo: .footnote))
                .foregroundStyle(Palette.goldText)
                .frame(width: 22, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(question.text)
                    .font(KFont.ui(16, .medium))
                    .foregroundStyle(Palette.ink)
                Text(question.label ?? question.type.title)
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                if !question.choices.isEmpty {
                    Text(question.choices.joined(separator: " · "))
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkDim)
                }
            }
            Spacer(minLength: 4)
            if !ui.live {
                Button {
                    Haptics.tap()
                    removing = question
                } label: {
                    Text("Remove")
                        .font(KFont.ui(14, .medium, relativeTo: .footnote))
                        .foregroundStyle(Palette.danger)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Remove \(question.text)")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 46) }
        }
    }

    // MARK: New question

    private var newQuestion: some View {
        FilesGroup(label: "New question") {
            VStack(alignment: .leading, spacing: 10) {
                field("Question", text: $questionText)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(DriveQuestionType.allCases, id: \.self) { item in
                            FilterPill(title: item.title, on: type == item) { type = item }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Question type")
                if type.needsChoices {
                    field("Choices, comma separated", text: $choicesText)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                pillButton("Add question", action: addQuestion)
            }
            .animation(Motion.snappy, value: type)
        }
    }

    private func addQuestion() {
        let text = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            ui.toaster.say("Write the question first")
            return
        }
        var choices: [String] = []
        if type.needsChoices {
            choices = choicesText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !choices.isEmpty else {
                ui.toaster.say("Add at least one choice")
                return
            }
        }
        if ui.live {
            addQuestionLive(DriveQuestion(text: text, type: type, choices: choices))
            return
        }
        withAnimation(Motion.snappy) {
            ui.store.addQuestion(fileID, DriveQuestion(text: text, type: type, choices: choices))
        }
        questionText = ""
        choicesText = ""
        Haptics.success()
        ui.toaster.say("Question added")
    }

    // MARK: Publishing and responses

    private func publishing(_ form: DriveForm) -> some View {
        FilesGroup(label: "Responses") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(form.published ? Palette.success : Palette.inkFaint)
                        .frame(width: 8, height: 8)
                    Text(form.published ? "Published and taking responses" : "Not published")
                        .font(KFont.ui(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                }
                HStack(spacing: 10) {
                    pillButton(form.published ? "Unpublish" : "Publish") {
                        if ui.live {
                            let on = !form.published
                            let name = form.title
                            ui.sheet = .confirm(DriveLiveConfirm(
                                title: on ? "Publish \(name)?" : "Unpublish \(name)?",
                                detail: on ? "Anyone with the form's link can open it and send answers."
                                           : "The form stops taking answers. Answers already sent stay.",
                                confirm: on ? "Publish" : "Unpublish", danger: !on
                            ) { run({ await ui.store.publishLive(fileID, on) }, done: on ? "Form published" : "Form unpublished") })
                            return
                        }
                        ui.store.setPublished(fileID, !form.published)
                        Haptics.success()
                        ui.toaster.say("Publish state updated")
                    }
                    pillButton("Load responses") {
                        Haptics.tap()
                        if ui.live {
                            loadResponsesLive()
                            return
                        }
                        withAnimation(Motion.snappy) { responses = form.responses }
                    }
                }
                if let responses {
                    responseList(responses)
                        .transition(.opacity)
                    if ui.live && moreResponses {
                        HintLine(text: "Showing the first \(responses.count) responses. See the rest in Google Forms.")
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 18)
        }
    }

    private func responseList(_ list: [String]) -> some View {
        DrivePaper {
            if list.isEmpty {
                Text("No responses yet.").font(KFont.ui(15))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(list.count) responses")
                        .font(KFont.ui(13, .semibold, relativeTo: .footnote))
                        .opacity(0.6)
                    ForEach(Array(list.enumerated()), id: \.offset) { _, line in
                        Text(line).font(KFont.ui(15))
                    }
                }
            }
        }
    }

    // MARK: Paired desktop

    /// Read the form. The title field follows the desktop only while the person has not changed it.
    private func loadLive() async {
        guard ui.live else { return }
        if liveRead == nil { liveLoad = .loading }
        do {
            let read = try await ui.store.formLive(fileID)
            show(read)
            liveLoad = .loaded
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            liveLoad = .failed("This form could not be read. " + error.plainWords)
        }
    }

    private func show(_ read: DriveDTOForm) {
        let fresh = read.info?.title ?? ""
        if title.trimmingCharacters(in: .whitespacesAndNewlines) == titleBase.trimmingCharacters(in: .whitespacesAndNewlines) {
            title = fresh
            titleBase = fresh
        }
        liveRead = read
    }

    /// One form change; the form is read again after, and the outcome said plainly.
    private func run(_ change: @escaping () async -> (DriveLiveOutcome, DriveDTOForm?), done: String,
                     after: @escaping (DriveLiveOutcome, DriveDTOForm?) -> Void = { _, _ in }) {
        guard !working else {
            ui.toaster.say("Wait for the last change to finish")
            return
        }
        liveNote = nil
        Task {
            let (outcome, read) = await change()
            after(outcome, read)
            if let read { show(read) }
            switch outcome {
            case .done:
                Haptics.success()
                ui.toaster.say(done)
            case .busy:
                ui.toaster.say("Wait for the last change to finish")
            case .failed(let why), .unconfirmed(let why):
                Haptics.thud()
                liveNote = why
            }
        }
    }

    /// Only a changed title is sent, and only if the desktop's title is still the one this field was filled from
    /// (the store reads it just before sending). If it changed, nothing is sent: the person's text stays and a
    /// second save sends it on purpose.
    private func saveTitleLive(_ clean: String) {
        guard clean != titleBase.trimmingCharacters(in: .whitespacesAndNewlines) else {
            ui.toaster.say("The title has not changed")
            return
        }
        let filledFrom = titleBase
        run({ await ui.store.formTitleLive(fileID, title: clean, filledFrom: filledFrom) }, done: "Form title saved") { outcome, read in
            if outcome == .done {
                titleBase = clean
            } else if let desktop = read?.info?.title, desktop != filledFrom {
                titleBase = desktop
            }
        }
    }

    /// Added at the end of the form as the desktop has it just before sending (the store reads it first).
    private func addQuestionLive(_ question: DriveQuestion) {
        run({ await ui.store.addQuestionLive(fileID, question) }, done: "Question added") { outcome, _ in
            if outcome == .done {
                questionText = ""
                choicesText = ""
            }
        }
    }

    private func loadResponsesLive() {
        guard let read = liveRead else { return }
        Task {
            do {
                let page = try await ui.store.formResponsesLive(fileID, form: read)
                moreResponses = page.more
                withAnimation(Motion.snappy) { responses = page.lines }
            } catch {
                if error is CancellationError { return }
                liveNote = "Responses could not be read. " + error.plainWords
            }
        }
    }

    // MARK: Small pieces

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .font(KFont.ui(16))
            .foregroundStyle(Palette.ink)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .kCard(radius: 14, raised: true)
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Palette.goldText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Palette.gold.opacity(0.14), in: Capsule())
        }
        .buttonStyle(PressStyle())
    }
}
