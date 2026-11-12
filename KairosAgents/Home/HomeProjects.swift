import SwiftUI

// Chat projects (core/projects.py on the desktop): shared instructions and documents for the chats in
// them. Home shows them as a row of tiles; a project opens to its own chats.

/// The projects as tiles in one row, then New project.
struct ProjectsRow: View {
    let projects: [ChatProject]
    let open: (ChatProject) -> Void

    @State private var creating = false
    private var store: ChatStore { ChatStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Projects")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(projects) { project in
                        Button {
                            Haptics.tap()
                            open(project)
                        } label: {
                            tile(symbol: "folder", title: project.name, detail: count(project))
                        }
                        .buttonStyle(PressStyle(scale: 0.96))
                        .accessibilityLabel("\(project.name), \(count(project))")
                    }
                    Button {
                        Haptics.tap()
                        creating = true
                    } label: {
                        tile(symbol: "plus", title: "New project", detail: "Shared instructions", faint: true)
                    }
                    .buttonStyle(PressStyle(scale: 0.96))
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .sheet(isPresented: $creating) {
            NewProjectSheet { open($0) }
        }
    }

    private func count(_ project: ChatProject) -> String {
        let chats = store.chats(inProject: project.id).count
        return chats == 1 ? "1 chat" : "\(chats) chats"
    }

    private func tile(symbol: String, title: String, detail: String, faint: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(faint ? Palette.inkDim : Palette.goldText)
            Text(title)
                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                .foregroundStyle(faint ? Palette.inkDim : Palette.ink)
                .lineLimit(1)
            Text(detail)
                .font(KFont.ui(12.5, relativeTo: .caption))
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
        .padding(12)
        .kCard(radius: 18, raised: !faint)
    }
}

/// "Move to project" in a chat's long-hold menu.
struct ProjectMenu: View {
    let conversation: Conversation
    @Environment(ChromeState.self) private var chrome
    private var store: ChatStore { ChatStore.shared }

    var body: some View {
        if !store.projects.isEmpty {
            Menu {
                ForEach(store.projects) { project in
                    Button(project.name, systemImage: project.id == conversation.projectID ? "checkmark" : "folder") {
                        move(to: project.id == conversation.projectID ? nil : project.id, name: project.name)
                    }
                }
                if conversation.projectID != nil {
                    Divider()
                    Button("Take out of the project", systemImage: "folder.badge.minus") { move(to: nil, name: nil) }
                }
            } label: {
                Label("Move to project", systemImage: "folder")
            }
        }
    }

    private func move(to projectID: String?, name: String?) {
        Haptics.select()
        Task {
            if let problem = await store.move(chat: conversation.id, toProject: projectID) {
                chrome.say(problem)
            } else {
                chrome.say(name.map { "Moved to \($0)" } ?? "Taken out of the project")
            }
        }
    }
}

/// One project: its instructions, its chats, and a new chat in it.
struct ProjectScreen: View {
    let projectID: String

    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    private var store: ChatStore { ChatStore.shared }

    var body: some View {
        let project = store.project(projectID)
        let chats = store.chats(inProject: projectID)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let project {
                    if !project.instructions.isEmpty || project.documentCount > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            if !project.instructions.isEmpty {
                                Text(project.instructions)
                                    .font(KFont.ui(15, relativeTo: .subheadline))
                                    .foregroundStyle(Palette.inkDim)
                                    .lineLimit(4)
                            }
                            if project.documentCount > 0 {
                                Label(project.documentCount == 1 ? "1 document" : "\(project.documentCount) documents", systemImage: "doc.on.doc")
                                    .font(KFont.ui(13, relativeTo: .footnote))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .kCard(radius: 20)
                    }

                    Button {
                        Haptics.tap()
                        router.push(.newChatInProject(projectID), on: .home)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Palette.onGold)
                                .frame(width: 34, height: 34)
                                .background(Palette.gold, in: Circle())
                            Text("New chat in this project")
                                .font(KFont.ui(16, .medium))
                                .foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .kCard(radius: 20, raised: true)
                    }
                    .buttonStyle(PressStyle(scale: 0.985))

                    if chats.isEmpty {
                        Text("No chats in this project yet. Start one above, or hold a chat on Home and move it here.")
                            .font(KFont.ui(14.5, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkFaint)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, 20)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(chats.enumerated()), id: \.element.id) { index, conversation in
                                Button { router.open(conversation) } label: {
                                    ConversationRow(conversation: conversation)
                                }
                                .buttonStyle(PressStyle(scale: 0.985))
                                .contextMenu { ProjectMenu(conversation: conversation) }
                                .arrives(min(index, 12) + 1)
                            }
                        }
                    }
                } else {
                    Text("This project is no longer on your desktop.")
                        .font(KFont.ui(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 30)
            .animation(Motion.snappy, value: chats)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refreshHome() }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text(project?.name ?? "Project")
                    .font(KFont.ui(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 64)
                HStack {
                    GlassIconButton(symbol: "chevron.left", label: "Back to Home") { dismiss() }
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .background { HeaderFade() }
        }
        .kScreen()
        .onChange(of: store.generation) { dismiss() }
    }
}

/// A name and instructions for a new project, made on the desktop.
struct NewProjectSheet: View {
    let made: (ChatProject) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var instructions = ""
    @State private var saving = false
    @State private var problem: String?
    @FocusState private var naming: Bool

    var body: some View {
        FittedSheet(estimate: 460) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New project")
                    .font(KFont.ui(20, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)

                TextField("Name", text: $name)
                    .font(KFont.ui(16.5))
                    .foregroundStyle(Palette.ink)
                    .focused($naming)
                    .padding(14)
                    .kCard(radius: 18)

                TextField("Instructions every chat in it follows (optional)", text: $instructions, axis: .vertical)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3...6)
                    .padding(14)
                    .kCard(radius: 18)

                if let problem {
                    Text(problem)
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.danger)
                }

                Button(action: save) {
                    Text(saving ? "Making it" : "Make project")
                        .font(KFont.ui(16, .semibold))
                        .foregroundStyle(Palette.onGold)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Palette.gold, in: Capsule())
                        .opacity(trimmedName.isEmpty || saving ? 0.5 : 1)
                }
                .buttonStyle(PressStyle(scale: 0.97))
                .disabled(trimmedName.isEmpty || saving)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .onAppear { naming = true }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        saving = true
        problem = nil
        Task {
            do {
                let project = try await ChatStore.shared.createProject(
                    name: trimmedName, instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines))
                Haptics.success()
                dismiss()
                made(project)
            } catch {
                saving = false
                problem = error.plainWords
            }
        }
    }
}
