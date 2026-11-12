import SwiftUI

// Settings pages for what a bot knows: memory, About you, skills and the skill library.

// MARK: - Memory

struct MemorySettings: View {
    let botID: String
    let store = BotsStore.shared
    @State private var newNote = ""
    @State private var newSection = "Notes"
    @State private var search = ""
    @State private var newTopic = ""
    @State private var tidying = false

    private let sections = ["About this work", "Preferences", "Corrections", "Notes"]

    var body: some View {
        let binding = store.binding(botID)
        let s = binding.wrappedValue
        BotsPage("Memory", subtitle: store.bot(botID).name) {
            BotsSection(footer: "When off, the bot neither reads nor saves notes.") {
                ToggleRow(title: "Use memory", symbol: "brain", isOn: binding.useMemory)
            }
            if !s.useMemory {
                HintLine(text: "Memory is off for this bot. Its notes are kept, but it does not read or add to them.", symbol: "pause.circle", color: Palette.goldText)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel(text: "How much it reads each turn")
                    Text("\(s.notes.count * 3) lines of 200").font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                }
                MeterBar(fraction: Double(s.notes.count * 3) / 200)
            }
            .padding(14)
            .kCard(radius: 18)

            TextField("Search its notes", text: $search)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .kCard(radius: 16)

            let shown = s.notes.filter { search.count < 2 || $0.text.localizedCaseInsensitiveContains(search) }
            BotsSection(title: "What it remembers") {
                if shown.isEmpty {
                    EmptyNote(text: s.notes.isEmpty ? "No notes yet. Add one below, or the bot adds its own as it learns." : "Nothing matches that search.", symbol: "note.text")
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, note in
                    if index > 0 { RowLine() }
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.section.uppercased()).font(KFont.label).tracking(1).foregroundStyle(Palette.goldText)
                            Text(note.text).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                            Text("Added by \(note.addedBy), \(note.when)").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: 0)
                        Button {
                            Haptics.tap()
                            withAnimation(Motion.snappy) { binding.wrappedValue.notes.removeAll { $0.id == note.id } }
                            store.say("Note removed")
                        } label: {
                            Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(Palette.danger).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Remove note")
                    }
                    .padding(.leading, 14)
                    .padding(.vertical, 6)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Add something to remember").padding(.horizontal, 4)
                VStack(spacing: 0) {
                    MenuRow(title: "Heading", options: sections, selection: $newSection)
                    RowLine()
                    TextField("Something it should already know", text: $newNote, axis: .vertical)
                        .font(KFont.ui(16))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1...4)
                        .padding(14)
                }
                .kCard(radius: 20)
                PillButton(title: "Add note", symbol: "plus", look: .filled, wide: true) {
                    let text = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { store.say("Write the note first."); return }
                    Haptics.success()
                    withAnimation(Motion.snappy) {
                        binding.wrappedValue.notes.insert(MemoryNote(section: newSection, text: String(text.prefix(1000)), addedBy: "you", when: "just now"), at: 0)
                    }
                    newNote = ""
                }
            }

            BotsSection(title: "Topics") {
                ForEach(Array(s.topics.enumerated()), id: \.offset) { index, topic in
                    if index > 0 { RowLine() }
                    HStack {
                        Image(systemName: "folder").foregroundStyle(Palette.goldText).frame(width: 26)
                        Text(topic).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        Spacer()
                        Button {
                            _ = withAnimation(Motion.snappy) { binding.wrappedValue.topics.remove(at: index) }
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(Palette.danger).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Delete topic \(topic)")
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 4)
                }
                RowLine()
                HStack {
                    TextField("Topic name", text: $newTopic)
                        .font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    PillButton(title: "Create topic") {
                        let name = newTopic.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { store.say("Give the topic a name."); return }
                        guard !s.topics.contains(name) else { store.say("A topic with that name already exists."); return }
                        withAnimation(Motion.snappy) { binding.wrappedValue.topics.append(name) }
                        newTopic = ""
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .frame(minHeight: 56)
            }

            BotsSection(title: "Keeping it tidy") {
                ToggleRow(title: "Keep its notes tidy", detail: "It reviews and cleans up what it remembers.", symbol: "sparkles", isOn: binding.tidyNotes)
                RowLine(inset: 54)
                ToggleRow(title: "Learn from rooms", detail: "It may save what is said in rooms it is in.", symbol: "number", isOn: binding.learnFromRooms)
                RowLine()
                HStack {
                    Text(tidying ? "Tidying" : "Last tidied this morning").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                    Spacer()
                    PillButton(title: "Tidy now", symbol: "wand.and.stars") {
                        tidying = true
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            tidying = false
                            store.say("Tidied 3 pages.")
                        }
                    }
                    .disabled(tidying)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
            }

            NavigationLink(value: BotsRoute.settings(botID, .aboutYou)) {
                NavRow(title: "About you", symbol: "person.text.rectangle", detail: "What every bot knows about you")
                    .kCard(radius: 20)
            }
            .buttonStyle(PressStyle(scale: 0.98))
        }
    }
}

// MARK: - About you

struct AboutYouSettings: View {
    let store = BotsStore.shared
    @State private var state = "Saved"
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        BotsPage("About you", subtitle: "Every bot reads this") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel(text: "About you")
                    HStack(spacing: 5) {
                        if state == "Saving" { ProgressView().controlSize(.mini) }
                        Text(state).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(state == "Saved" ? Palette.success : Palette.inkFaint)
                    }
                }
                .padding(.horizontal, 4)
                TextField("Anything every bot should know about you: your name, your work, how you like things done.", text: Binding(
                    get: { store.aboutYou },
                    set: { value in
                        store.aboutYou = value
                        autosave()
                    }
                ), axis: .vertical)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .lineLimit(5...14)
                .padding(14)
                .kCard(radius: 18)
                Text("\(store.aboutYou.count) / 24,000 characters")
                    .font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint).padding(.horizontal, 4)
            }

            BotsSection(title: "Learned by your bots", footer: "Facts your bots pick up from chats. Remove any of them and bots will not learn it again.") {
                if store.learned.isEmpty {
                    EmptyNote(text: "Nothing learned yet. Facts your bots pick up from chats appear here, and you can remove any of them.", symbol: "lightbulb")
                }
                ForEach(Array(store.learned.enumerated()), id: \.element.id) { index, fact in
                    if index > 0 { RowLine() }
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.text).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                            Text("Learned by \(fact.who), \(fact.when)").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        PillButton(title: "Remove", look: .danger) {
                            Haptics.tap()
                            withAnimation(Motion.snappy) { store.learned.removeAll { $0.id == fact.id } }
                            store.say("Removed. Bots will not learn that again.")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func autosave() {
        state = "Unsaved"
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            state = "Saving"
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.gentle) { state = "Saved" }
        }
    }
}

// MARK: - Skills

struct SkillsSettings: View {
    let botID: String
    let store = BotsStore.shared
    @State private var reviewing: SkillItem?
    @State private var writing = false
    @State private var importing = false

    var body: some View {
        let binding = store.binding(botID)
        let s = binding.wrappedValue
        let waiting = s.skills.filter { $0.state == .needsReview || $0.state == .changed }
        BotsPage("Skills", subtitle: "\(s.skills.filter { $0.state == .on }.count) on of \(s.skills.count)", trailing: {
            Menu {
                Button { importing = true } label: { Label("Import from a link", systemImage: "link") }
                Button { writing = true } label: { Label("Write a command", systemImage: "square.and.pencil") }
            } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .kGlass(Circle(), interactive: true)
            .accessibilityLabel("Add a skill")
        }) {
            if !waiting.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Waiting for you").padding(.horizontal, 4)
                    ForEach(waiting) { skill in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("/\(skill.name)").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                            Text(skill.about).font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
                            Text("Review the full text before this skill is switched on.").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                            HStack(spacing: 8) {
                                PillButton(title: "Not now", wide: true) {
                                    update(skill.id) { $0.state = .off }
                                    store.say("Not now.")
                                }
                                PillButton(title: "Review", look: .filled, wide: true) { reviewing = skill }
                            }
                        }
                        .padding(14)
                        .kCard(radius: 20, raised: true)
                    }
                }
            }

            BotsSection(title: "Skills", footer: "Only reviewed skills switched on for this bot are available. Use one in chat with its /name.") {
                if s.skills.isEmpty {
                    EmptyNote(text: "No skills yet. Teach one in chat with /learn.", symbol: "bolt")
                }
                ForEach(Array(s.skills.enumerated()), id: \.element.id) { index, skill in
                    if index > 0 { RowLine() }
                    skillRow(skill)
                }
            }

            BotsSection(title: "Learning") {
                ToggleRow(title: "Look for skills in finished work", detail: "It suggests a skill when it repeats a job.", isOn: binding.lookForSkills)
                RowLine()
                MenuRow(title: "Share learned skills", options: ["Off", "Ask", "Auto"], selection: binding.shareLearned)
            }

            NavigationLink(value: BotsRoute.settings(botID, .skillLibrary)) {
                NavRow(title: "Open the skill library", symbol: "books.vertical", detail: "\(store.skillLibrary.count) skills you can give any bot")
                    .kCard(radius: 20)
            }
            .buttonStyle(PressStyle(scale: 0.98))
        }
        .sheet(item: $reviewing) { skill in
            SkillReviewSheet(skill: skill) {
                update(skill.id) { $0.state = .on }
                store.say("Enabled as /\(skill.name).")
            }
        }
        .sheet(isPresented: $writing) {
            WriteSkillSheet { skill in
                withAnimation(Motion.snappy) { binding.wrappedValue.skills.append(skill) }
                store.say("Saved /\(skill.name)")
            }
        }
        .sheet(isPresented: $importing) {
            ImportSkillSheet { name in
                let skill = SkillItem(name: name, origin: "Imported", about: "Imported from a link.", state: .needsReview, text: "Imported skill text. Review it before turning it on.")
                withAnimation(Motion.snappy) { binding.wrappedValue.skills.append(skill) }
                store.say("1 skill added, switched off until you review it")
            }
        }
    }

    private func skillRow(_ skill: SkillItem) -> some View {
        HStack(spacing: 12) {
            Button { reviewing = skill } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("/\(skill.name)").font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                        if skill.everyBot {
                            Text("Every bot").font(KFont.ui(11.5, .medium, relativeTo: .caption2)).foregroundStyle(Palette.goldText)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Palette.gold.opacity(0.15), in: Capsule())
                        }
                    }
                    Text("\(skill.origin) · \(skill.about)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(2)
                    if skill.state == .needsReview {
                        Text("Needs review").font(KFont.ui(12.5, .medium, relativeTo: .caption)).foregroundStyle(Palette.goldText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            Toggle("", isOn: Binding(
                get: { skill.state == .on },
                set: { on in
                    if on && skill.state != .off {
                        reviewing = skill
                    } else {
                        Haptics.select()
                        update(skill.id) { $0.state = on ? .on : .off }
                    }
                }
            ))
            .labelsHidden()
            .tint(Palette.gold)
            .accessibilityLabel(skill.state == .on ? "Turn off /\(skill.name)" : "Review and turn on /\(skill.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
    }

    private func update(_ id: UUID, _ change: (inout SkillItem) -> Void) {
        let binding = store.binding(botID)
        guard let index = binding.wrappedValue.skills.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Motion.snappy) { change(&binding.wrappedValue.skills[index]) }
    }
}

struct SkillReviewSheet: View {
    let skill: SkillItem
    let enable: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 480) {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: "/\(skill.name)", detail: "\(skill.origin) · \(skill.about)")
                SectionLabel(text: "Full text")
                Text(skill.text)
                    .font(.system(size: 14.5, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kCard(radius: 16)
                HintLine(text: "Read it all before switching it on. A skill can tell the bot to do anything its access allows.", symbol: "eye")
                if skill.state == .on {
                    GoldButton(title: "Done") { dismiss() }
                } else {
                    GoldButton(title: "Enable reviewed skill") {
                        Haptics.success()
                        enable()
                        dismiss()
                    }
                }
                QuietButton(title: "Not now") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

struct WriteSkillSheet: View {
    let save: (SkillItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var line = ""
    @State private var instructions = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: "Write a command", detail: "Use it in chat as /name.")
                FieldCard(title: "Command name", text: $name, placeholder: "weekly-report", limit: 64)
                if let problem { HintLine(text: problem, symbol: "exclamationmark.circle", color: Palette.danger) }
                FieldCard(title: "One line", text: $line, placeholder: "What it is for", limit: 1024)
                FieldCard(title: "Instructions", text: $instructions, placeholder: "The steps it should follow", limit: 16_000, lines: 4...10)
                GoldButton(title: "Save command") {
                    guard problem == nil, !name.isEmpty, !instructions.isEmpty else { Haptics.thud(); return }
                    save(SkillItem(name: name, origin: "Written by you", about: line, state: .on, text: instructions))
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .kSheet()
    }

    private var problem: String? {
        if name.isEmpty { return nil }
        if ["goal", "learn", "setup"].contains(name) { return "That name is taken by a built-in command." }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        if !name.allSatisfy({ allowed.contains($0) }) { return "Use lowercase letters, numbers and hyphens." }
        return nil
    }
}

struct ImportSkillSheet: View {
    let add: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""

    var body: some View {
        FittedSheet(estimate: 360) {
            VStack(spacing: 14) {
                SheetTitle(title: "Import from a link", detail: "A GitHub link, owner/repo or a skills page. Imported skills stay off until you review them.")
                FieldCard(title: "Link", text: $link, placeholder: "owner/repo")
                GoldButton(title: "Import") {
                    let name = link.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
                    guard !name.isEmpty else { Haptics.thud(); return }
                    add(name)
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Skill library

struct SkillLibrarySettings: View {
    let botID: String
    let store = BotsStore.shared
    @State private var search = ""

    var body: some View {
        let binding = store.binding(botID)
        let items = store.skillLibrary.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.about.localizedCaseInsensitiveContains(search) }
        BotsPage("Skill library", subtitle: "Library (\(store.skillLibrary.count))") {
            TextField("Search skills", text: $search)
                .font(KFont.ui(16)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 14).frame(minHeight: 48).kCard(radius: 16)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, skill in
                let given = binding.wrappedValue.skills.contains { $0.name == skill.name }
                VStack(alignment: .leading, spacing: 4) {
                    Text("/\(skill.name)").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink).padding(.horizontal, 14).padding(.top, 12)
                    Text("\(skill.origin) · \(skill.about)").font(KFont.ui(13.5)).foregroundStyle(Palette.inkFaint).padding(.horizontal, 14)
                    ToggleRow(title: "Every bot", isOn: Binding(
                        get: { skill.everyBot },
                        set: { value in
                            if let i = store.skillLibrary.firstIndex(where: { $0.id == skill.id }) { store.skillLibrary[i].everyBot = value }
                        }
                    ))
                    RowLine()
                    ToggleRow(title: "This bot", isOn: Binding(
                        get: { given },
                        set: { value in
                            if value {
                                var copy = skill
                                copy.state = skill.state == .needsReview ? .needsReview : .on
                                binding.wrappedValue.skills.append(copy)
                                store.say(copy.state == .on ? "Given to \(store.bot(botID).name)" : "Added. Review it in Skills to turn it on.")
                            } else {
                                binding.wrappedValue.skills.removeAll { $0.name == skill.name }
                            }
                        }
                    ))
                }
                .kCard(radius: 20)
                .arrives(index)
            }
            if items.isEmpty {
                EmptyNote(text: "Nothing matches that search.", symbol: "magnifyingglass").kCard(radius: 20)
            }
        }
    }
}
