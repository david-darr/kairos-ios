import SwiftUI
import UniformTypeIdentifiers

// Administration: users, logs, runs, sandbox changes, file checkpoints, hooks, backups and system,
// and the desktop's keyboard shortcuts. Sample data only.

// MARK: - Sample data

nonisolated struct AdminUser: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var colorHex: UInt32
    var isAdmin: Bool
    var twoStep: Bool
    var thisComputer: Bool
    var isYou = false
}

nonisolated struct AdminLogLine: Identifiable, Hashable, Sendable {
    let id = UUID()
    var time: String
    var level: String
    var area: String
    var text: String
    var chat: String?
}

nonisolated struct AdminRun: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var outcome: String
    var when: String
    var steps: [String]
}

nonisolated struct ChangeSet: Identifiable, Hashable, Sendable {
    let id: String
    var chat: String
    var when: String
    var files: [String]
    var diff: [String]
    var tooLarge = false
}

nonisolated struct Checkpoint: Identifiable, Hashable, Sendable {
    let id: String
    var source: String
    var when: String
    var files: [String]
    var restored: Int
}

nonisolated struct Hook: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var event: String
    var action: String
    var tools: String
    var agent: String
    var source: String
    var target: String
    var template: String
    var timeout: Int
    var blocks: Bool
    var on: Bool
    var lastRun: String
    var outcome: String
}

@Observable
final class AdminSample {
    static let shared = AdminSample()

    static let events = ["Before a tool runs", "After a tool runs", "A chat finishes", "A task runs", "A bot reports"]
    static let actions = ["Post to a web address", "Add to a vault note", "Send to a channel", "Run a command"]

    var users: [AdminUser] = [
        AdminUser(id: "u1", name: "Sam", colorHex: 0xD9B260, isAdmin: true, twoStep: true, thisComputer: true, isYou: true),
        AdminUser(id: "u2", name: "Alex", colorHex: 0x5FAFA8, isAdmin: false, twoStep: false, thisComputer: false),
        AdminUser(id: "u3", name: "Robin", colorHex: 0xB49ACF, isAdmin: false, twoStep: true, thisComputer: true),
    ]

    var hooks: [Hook] = [
        Hook(id: "h1", name: "Log finished chats", event: "A chat finishes", action: "Add to a vault note", tools: "", agent: "Any agent", source: "Anywhere",
             target: "Logs/Chats.md", template: "{time} {summary}", timeout: 30, blocks: false, on: true, lastRun: "9:12", outcome: "OK"),
        Hook(id: "h2", name: "Block shell deletes", event: "Before a tool runs", action: "Run a command", tools: "shell|bash", agent: "Any agent", source: "Anywhere",
             target: "check-delete --strict", template: "", timeout: 10, blocks: true, on: true, lastRun: "Yesterday", outcome: "Blocked"),
        Hook(id: "h3", name: "Post task results", event: "A task runs", action: "Post to a web address", tools: "", agent: "Producer", source: "Tasks only",
             target: "https://hooks.example.com/kairos", template: "{task}: {reply}", timeout: 30, blocks: false, on: false, lastRun: "Not run yet", outcome: ""),
    ]
    var paused = false
}

// MARK: - Users

struct UsersScreen: View {
    @Bindable private var sample = AdminSample.shared
    @State private var chosen: AdminUser?
    @State private var adding = false

    var body: some View {
        SettingsPage("Users", subtitle: "Admin. Who can open this Kairos, and what they may do.") {
            SettingsGroup("People", footer: "This computer lets a member run things on the desktop itself. Admins always can.") {
                ForEach(Array(sample.users.enumerated()), id: \.element.id) { index, user in
                    HStack(spacing: 12) {
                        Button { chosen = user } label: {
                            HStack(spacing: 12) {
                                Text(String(user.name.prefix(1)))
                                    .font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                                    .frame(width: 40, height: 40)
                                    .background(Color(hex: user.colorHex).opacity(0.3), in: Circle())
                                    .overlay(Circle().strokeBorder(Color(hex: user.colorHex), lineWidth: 2))
                                RowLabel(title: user.name + (user.isYou ? " (you)" : ""), detail: [user.isAdmin ? "Admin" : "Member", user.twoStep ? "two-step on" : nil].compactMap { $0 }.joined(separator: " · "))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        if user.isAdmin {
                            StatusPill(text: "Full access", tone: .ok)
                        } else {
                            Toggle("This computer for \(user.name)", isOn: Binding(get: { sample.users[index].thisComputer }, set: { sample.users[index].thisComputer = $0 }))
                                .labelsHidden().tint(Palette.gold)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                ActionRow(title: "Add user", symbol: "person.badge.plus", tone: .gold) { adding = true }
            }
        }
        .sheet(item: $chosen) { user in UserSheet(user: user) }
        .sheet(isPresented: $adding) { AddUserSheet() }
    }
}

private struct UserSheet: View {
    let user: AdminUser
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var note: String?
    @State private var confirmDelete = false
    private let sample = AdminSample.shared

    var body: some View {
        FittedSheet(estimate: 520) {
            VStack(alignment: .leading, spacing: 18) {
                Text(user.name).font(KFont.display(32)).foregroundStyle(Palette.ink).padding(.top, 30)
                SettingsGroup("Reset password", footer: "Eight or more characters. They are signed out everywhere.") {
                    FieldRow(title: "New password", text: $password, prompt: "8 or more characters", secure: true)
                    ActionRow(title: "Set password", symbol: "key") {
                        guard password.count >= 8 else { note = "Use 8 or more characters."; return }
                        password = ""
                        note = nil
                        YouStore.shared.say("\(user.name) has a new password and was signed out")
                    }
                }
                if let note { Text(note).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.danger) }
                if !user.isYou {
                    SettingsGroup {
                        ActionRow(title: user.isAdmin ? "Make member" : "Make admin", symbol: "person.badge.key") {
                            if let index = sample.users.firstIndex(where: { $0.id == user.id }) { sample.users[index].isAdmin.toggle() }
                            YouStore.shared.say("\(user.name) is \(user.isAdmin ? "a member" : "an admin") now")
                            dismiss()
                        }
                        ActionRow(title: "Delete user", symbol: "trash", tone: .danger) { confirmDelete = true }
                    }
                } else {
                    NoteText(text: "You cannot delete yourself or change your own role.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .confirmationDialog("Delete \(user.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                sample.users.removeAll { $0.id == user.id }
                YouStore.shared.say("\(user.name) was deleted")
                dismiss()
            }
        } message: {
            Text("Their account and everything in it is removed.")
        }
    }
}

private struct AddUserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var password = ""
    @State private var admin = false
    @State private var note: String?
    private let sample = AdminSample.shared

    var body: some View {
        FittedSheet(estimate: 460) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add user").font(KFont.ui(22, .semibold, relativeTo: .title2)).foregroundStyle(Palette.ink).padding(.top, 30)
                SettingsGroup {
                    FieldRow(title: "Username", text: $name, prompt: "name")
                    FieldRow(title: "Password", text: $password, prompt: "8 or more characters", secure: true)
                    ToggleRow(title: "Admin", detail: "Can change every setting", isOn: $admin)
                }
                if let note { Text(note).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.danger) }
                GoldButton(title: "Add user") {
                    let clean = name.trimmingCharacters(in: .whitespaces)
                    guard !clean.isEmpty else { note = "Enter a username."; return }
                    guard password.count >= 8 else { note = "Use 8 or more characters for the password."; return }
                    guard !sample.users.contains(where: { $0.name.lowercased() == clean.lowercased() }) else { note = "That username is taken."; return }
                    sample.users.append(AdminUser(id: UUID().uuidString, name: clean, colorHex: YouStore.accountColors[sample.users.count % YouStore.accountColors.count].hex, isAdmin: admin, twoStep: false, thisComputer: admin))
                    YouStore.shared.say("\(clean) added")
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Logs

struct LogsScreen: View {
    @State private var file = "Backend"
    @State private var level = "All levels"
    @State private var area = "Every area"
    @State private var time = "Any time"
    @State private var chat = "Any chat or task"
    @State private var query = ""
    @State private var follow = false
    @State private var lines: [AdminLogLine] = [
        AdminLogLine(time: "9:41:02", level: "Info", area: "Chat", text: "Turn finished in 12.4 s", chat: "Bike shop launch"),
        AdminLogLine(time: "9:40:51", level: "Warning", area: "Remote", text: "Phone reconnected after 3 s"),
        AdminLogLine(time: "9:38:10", level: "Info", area: "Tasks", text: "Morning brief ran and delivered"),
        AdminLogLine(time: "9:31:44", level: "Error", area: "Discord", text: "Send failed: the channel is missing", chat: "Content team"),
        AdminLogLine(time: "9:12:03", level: "Info", area: "Skills", text: "Loaded 14 skills"),
    ]

    private var shown: [AdminLogLine] {
        lines.filter { line in
            (level == "All levels" || (level == "Warnings and errors" && line.level != "Info") || (level == "Errors only" && line.level == "Error"))
                && (area == "Every area" || line.area == area)
                && (chat == "Any chat or task" || line.chat == chat)
                && (query.isEmpty || line.text.lowercased().contains(query.lowercased()))
        }
    }

    var body: some View {
        SettingsPage("Logs", subtitle: "Admin. What your desktop wrote down.") {
            SettingsGroup {
                PickRow(title: "Log", selection: $file, options: ["Backend", "Errors", "Desktop"]) { name in
                    "\(name) · \(name == "Backend" ? "2.4 MB" : name == "Errors" ? "84 kB" : "610 kB")"
                }
                PickRow(title: "Level", selection: $level, options: ["All levels", "Warnings and errors", "Errors only"]) { $0 }
                PickRow(title: "Area", selection: $area, options: ["Every area", "Chat", "Swarm", "Tasks", "Remote", "Discord", "Skills"]) { $0 }
                PickRow(title: "Time", selection: $time, options: ["Any time", "Last hour", "Today", "Last week"]) { $0 }
                PickRow(title: "Chat", selection: $chat, options: ["Any chat or task", "Bike shop launch", "Content team"]) { $0 }
                ToggleRow(title: "Follow", detail: "New lines appear as they are written", isOn: $follow)
            }
            SearchField(prompt: "Search the log", text: $query)
            VStack(alignment: .leading, spacing: 0) {
                if shown.isEmpty {
                    EmptyRow(text: lines.isEmpty ? "Nothing written to this log yet." : "No lines match.")
                }
                ForEach(shown) { line in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(line.time).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.inkFaint)
                            StatusPill(text: line.level, tone: line.level == "Error" ? .bad : line.level == "Warning" ? .warn : .muted)
                            Text(line.area).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                            if let chat = line.chat {
                                Text(chat).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.goldText).lineLimit(1)
                            }
                        }
                        Text(line.text).font(.system(size: 13.5, design: .monospaced)).foregroundStyle(line.level == "Error" ? Palette.danger : Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .kCard(radius: 20)
        }
        .task(id: follow) {
            guard follow else { return }
            var count = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                count += 1
                withAnimation(Motion.snappy) {
                    lines.insert(AdminLogLine(time: "9:42:\(String(format: "%02d", count * 2))", level: "Info", area: "Chat", text: "Heartbeat \(count): live stream healthy"), at: 0)
                    if lines.count > 1000 { lines.removeLast() }
                }
            }
        }
    }
}

// MARK: - Runs

struct RunsScreen: View {
    @State private var filter = "Every run"
    @State private var open: String?
    private let runs: [AdminRun] = [
        AdminRun(id: "r1", title: "Morning brief", outcome: "Finished", when: "8:00", steps: ["Read the calendar", "Read important mail", "Wrote the brief", "Sent it to Telegram"]),
        AdminRun(id: "r2", title: "Content team cycle", outcome: "Failed", when: "7:30", steps: ["Picked a topic", "Wrote a script", "Render failed: out of disk space"]),
        AdminRun(id: "r3", title: "Price check", outcome: "Stopped", when: "Yesterday", steps: ["Searched the first shop", "Stopped by you"]),
        AdminRun(id: "r4", title: "Receipt filing", outcome: "Finished", when: "Monday", steps: ["Read 6 receipts", "Filed them under October"]),
    ]

    private var shown: [AdminRun] { runs.filter { filter == "Every run" || $0.outcome == filter } }

    var body: some View {
        SettingsPage("Runs", subtitle: "Admin. The last 100 runs of tasks and bots.") {
            ChipPicker(items: ["Every run", "Failed", "Stopped", "Finished"], selection: $filter) { $0 }
            SettingsGroup {
                if shown.isEmpty { EmptyRow(text: "No \(filter.lowercased()) runs.") }
                ForEach(shown) { run in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            Haptics.select()
                            withAnimation(Motion.snappy) { open = open == run.id ? nil : run.id }
                        } label: {
                            HStack {
                                RowLabel(title: run.title, detail: run.when)
                                StatusPill(text: run.outcome, tone: run.outcome == "Failed" ? .bad : run.outcome == "Stopped" ? .warn : .ok)
                                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                                    .rotationEffect(.degrees(open == run.id ? 180 : 0))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                        .accessibilityLabel("\(run.title), \(run.outcome). Steps")
                        if open == run.id {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(run.steps.enumerated()), id: \.offset) { index, step in
                                    HStack(alignment: .top, spacing: 10) {
                                        Circle().fill(index == run.steps.count - 1 && run.outcome == "Failed" ? Palette.danger : Palette.gold)
                                            .frame(width: 8, height: 8).padding(.top, 6)
                                        Text(step).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                                    }
                                }
                            }
                            .padding(.leading, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
        }
    }
}

// MARK: - Sandbox changes

struct SandboxScreen: View {
    @State private var sets: [ChangeSet] = [
        ChangeSet(id: "cs-7f2", chat: "Faster image loading", when: "Today 9:20", files: ["static/js/gallery.js · changed", "static/css/gallery.css · changed"],
                  diff: ["@@ gallery.js", "-  img.src = full;", "+  img.loading = \"lazy\";", "+  img.src = thumb;", "@@ gallery.css", "+.gallery img { aspect-ratio: 4 / 3; }"]),
        ChangeSet(id: "cs-1a9", chat: "Rename the shop", when: "Yesterday", files: ["240 files"], diff: [], tooLarge: true),
    ]
    @State private var showing: String?
    @State private var applying: ChangeSet?
    @State private var discarding: ChangeSet?

    var body: some View {
        SettingsPage("Sandbox changes", subtitle: "Admin. File changes a chat made in a sandbox, waiting for you.") {
            if sets.isEmpty {
                EmptyRow(text: "No sandbox changes waiting.").kCard(radius: 22)
            }
            ForEach(sets) { set in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(set.id).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.inkFaint)
                        Spacer()
                        Text(set.when).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                    Text(set.chat).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                    ForEach(set.files, id: \.self) { file in
                        Text(file).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.inkDim)
                    }
                    if showing == set.id {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(set.diff.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(line.hasPrefix("+") ? Palette.success : line.hasPrefix("-") ? Palette.danger : Palette.inkFaint)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(10)
                        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if set.tooLarge {
                        NoteText(text: "This change is too large to apply from here. Review it on your desktop.")
                    }
                    HStack(spacing: 6) {
                        if !set.diff.isEmpty {
                            PillButton(title: showing == set.id ? "Hide diff" : "Show diff") {
                                withAnimation(Motion.snappy) { showing = showing == set.id ? nil : set.id }
                            }
                        }
                        if !set.tooLarge {
                            PillButton(title: "Apply", prominent: true) { applying = set }
                        }
                        PillButton(title: "Discard", danger: true) { discarding = set }
                    }
                }
                .padding(16)
                .kCard(radius: 22)
            }
            NoteText(text: "Files must be unchanged since the run. Change sets expire after seven days.")
        }
        .confirmationDialog("Apply \(applying?.id ?? "")?", isPresented: Binding(get: { applying != nil }, set: { if !$0 { applying = nil } }), titleVisibility: .visible) {
            Button("Apply") {
                if let id = applying?.id { withAnimation(Motion.snappy) { sets.removeAll { $0.id == id } } }
                applying = nil
                YouStore.shared.say("Applied. Nothing was committed.")
            }
            Button("Cancel", role: .cancel) { applying = nil }
        } message: {
            Text("This writes the files into the Kairos folder. Nothing is committed.")
        }
        .confirmationDialog("Discard \(discarding?.id ?? "")?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }), titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                if let id = discarding?.id { withAnimation(Motion.snappy) { sets.removeAll { $0.id == id } } }
                discarding = nil
            }
            Button("Cancel", role: .cancel) { discarding = nil }
        }
    }
}

// MARK: - File checkpoints

struct CheckpointsScreen: View {
    @State private var checkpoints: [Checkpoint] = [
        Checkpoint(id: "k1", source: "Chat: Bike shop launch", when: "Today 9:02", files: ["Launch plan.md", "Prices.md", "Daily/2026-11-12.md"], restored: 0),
        Checkpoint(id: "k2", source: "Task: Receipt filing", when: "Monday", files: ["Money/October.md"], restored: 1),
    ]
    @State private var open: String?
    @State private var selected: Set<String> = []
    @State private var confirming: Checkpoint?

    var body: some View {
        SettingsPage("File checkpoints", subtitle: "Admin. Each turn saves the vault and working files it touched, so you can put them back.") {
            ForEach(checkpoints) { point in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        RowLabel(title: point.source, detail: "\(point.when) · \(point.files.count) files · \(point.restored) restored")
                        PillButton(title: open == point.id ? "Close" : "Review") {
                            withAnimation(Motion.snappy) {
                                open = open == point.id ? nil : point.id
                                selected = []
                            }
                        }
                    }
                    if open == point.id {
                        if point.restored == point.files.count {
                            NoteText(text: "Nothing left to restore.")
                        }
                        ForEach(point.files, id: \.self) { file in
                            let changedAgain = file == "Daily/2026-11-12.md"
                            Toggle(isOn: Binding(get: { selected.contains(file) }, set: { on in
                                if on { selected.insert(file) } else { selected.remove(file) }
                            })) {
                                RowLabel(title: file, detail: changedAgain ? "Changed again since. It cannot be restored." : nil)
                            }
                            .tint(Palette.gold)
                            .disabled(changedAgain)
                        }
                        if !selected.isEmpty {
                            PillButton(title: "Restore \(selected.count) \(selected.count == 1 ? "file" : "files")", prominent: true) { confirming = point }
                        }
                    }
                }
                .padding(16)
                .kCard(radius: 22)
            }
            NoteText(text: "When two turns overlap, restoring one can undo part of the other. Check before you restore.", symbol: "exclamationmark.triangle")
        }
        .confirmationDialog("Restore the selected files?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                if let id = confirming?.id, let index = checkpoints.firstIndex(where: { $0.id == id }) {
                    checkpoints[index].restored += selected.count
                }
                YouStore.shared.say("Restored \(selected.count) to how they were before the turn")
                selected = []
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text("They go back to how they were before that turn.")
        }
    }
}

// MARK: - Hooks

struct HooksScreen: View {
    @Bindable private var sample = AdminSample.shared

    var body: some View {
        SettingsPage("Hooks", subtitle: "Admin. Small actions that run when something happens.") {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) { sample.paused.toggle() }
            } label: {
                Text(sample.paused ? "Resume all" : "Pause all").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 16).frame(height: 44)
            }
            .buttonStyle(PressStyle())
            .kGlass(Capsule(), interactive: true)
        } content: {
            if sample.paused {
                NoteText(text: "Every hook is paused. Nothing runs until you resume.", symbol: "pause.fill")
            }
            SettingsGroup {
                if sample.hooks.isEmpty { EmptyRow(text: "No hooks yet. Add one to log, alert or block.") }
                ForEach(Array(sample.hooks.enumerated()), id: \.element.id) { index, hook in
                    HStack(spacing: 10) {
                        NavigationLink(value: YouRoute.hook(hook.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(hook.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                    if !hook.outcome.isEmpty {
                                        StatusPill(text: hook.outcome, tone: hook.outcome == "OK" ? .ok : hook.outcome == "Blocked" ? .warn : .bad)
                                    }
                                }
                                Text("\(hook.event) · \(hook.action) · \(hook.lastRun)").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        Toggle("Turn \(hook.name) on", isOn: Binding(get: { sample.hooks[index].on }, set: { sample.hooks[index].on = $0 }))
                            .labelsHidden().tint(Palette.gold)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .opacity(sample.paused ? 0.6 : 1)
                }
                NavRow(title: "Add a hook", symbol: "plus", to: .editHook("new"))
            }
            SettingsGroup("Recent runs") {
                ValueRow(title: "Log finished chats", detail: "A chat finishes · 9:12", value: "OK")
                ValueRow(title: "Block shell deletes", detail: "Before a tool runs · yesterday", value: "Blocked")
                ValueRow(title: "Log finished chats", detail: "A chat finishes · yesterday", value: "Timed out")
            }
            NoteText(text: "Hooks see the tools of Claude, local and API models. Codex's own shell and file tools are out of their sight. Hooks never set off other hooks.")
        }
    }
}

struct HookDetailScreen: View {
    let hookID: String
    @Environment(\.dismiss) private var dismiss
    @Bindable private var sample = AdminSample.shared
    @State private var testResult: String?
    @State private var confirmDelete = false

    private var index: Int? { sample.hooks.firstIndex { $0.id == hookID } }

    var body: some View {
        SettingsPage(index.map { sample.hooks[$0].name } ?? "Hook", subtitle: index.map { "\(sample.hooks[$0].event) · \(sample.hooks[$0].action)" }) {
            if let index {
                let hook = sample.hooks[index]
                SettingsGroup {
                    ToggleRow(title: "On", isOn: $sample.hooks[index].on)
                    ValueRow(title: "Event", value: hook.event)
                    ValueRow(title: "Tools", value: hook.tools.isEmpty ? "Every tool" : hook.tools)
                    ValueRow(title: "Agent", value: hook.agent)
                    ValueRow(title: "Source", value: hook.source)
                }
                SettingsGroup(hook.action) {
                    switch hook.action {
                    case "Post to a web address":
                        ValueRow(title: "Address", value: hook.target)
                        ValueRow(title: "Signed", value: "Yes")
                    case "Add to a vault note":
                        ValueRow(title: "Note", value: hook.target)
                        ValueRow(title: "Line", value: hook.template)
                    case "Send to a channel":
                        ValueRow(title: "Channel", value: hook.target)
                        ValueRow(title: "Message", value: hook.template)
                    default:
                        ValueRow(title: "Command", value: hook.target)
                        ValueRow(title: "Timeout", value: "\(hook.timeout) s")
                        ValueRow(title: "Failure blocks the tool", value: hook.blocks ? "Yes" : "No")
                    }
                }
                SettingsGroup {
                    ActionRow(title: "Send a test event", symbol: "paperplane", trailing: testResult) {
                        testResult = "Sending..."
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            withAnimation(Motion.snappy) { testResult = hook.blocks ? "Would block" : "OK" }
                        }
                    }
                    NavRow(title: "Edit", symbol: "pencil", to: .editHook(hook.id))
                    ActionRow(title: "Delete hook", symbol: "trash", tone: .danger) { confirmDelete = true }
                }
                SettingsGroup("Recent runs") {
                    ValueRow(title: hook.lastRun, value: hook.outcome.isEmpty ? "Not run yet" : hook.outcome)
                }
            } else {
                EmptyRow(text: "This hook was deleted.").kCard(radius: 22)
            }
        }
        .confirmationDialog("Delete this hook?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                sample.hooks.removeAll { $0.id == hookID }
                YouStore.shared.say("Hook deleted")
                dismiss()
            }
        }
    }
}

struct HookEditScreen: View {
    let hookID: String
    @Environment(\.dismiss) private var dismiss
    @State private var hook = Hook(id: "new", name: "", event: AdminSample.events[1], action: AdminSample.actions[0], tools: "", agent: "Any agent", source: "Anywhere",
                                   target: "", template: "{time} {summary}", timeout: 30, blocks: false, on: true, lastRun: "Not run yet", outcome: "")
    @State private var note: String?
    @State private var confirmCommand = false
    @State private var loaded = false
    private let sample = AdminSample.shared

    private let examples: [(String, Hook)] = [
        ("Post to a web address", Hook(id: "", name: "Post chat summaries", event: "A chat finishes", action: "Post to a web address", tools: "", agent: "Any agent", source: "Chats only", target: "https://hooks.example.com/in", template: "{summary}", timeout: 30, blocks: false, on: true, lastRun: "", outcome: "")),
        ("Log to a vault note", Hook(id: "", name: "Log tool use", event: "After a tool runs", action: "Add to a vault note", tools: "*", agent: "Any agent", source: "Anywhere", target: "Logs/Tools.md", template: "{time} {agent} used {tool}", timeout: 30, blocks: false, on: true, lastRun: "", outcome: "")),
        ("Channel alert", Hook(id: "", name: "Alert on reports", event: "A bot reports", action: "Send to a channel", tools: "", agent: "Any agent", source: "Agents only", target: "Telegram", template: "{agent}: {card}", timeout: 30, blocks: false, on: true, lastRun: "", outcome: "")),
        ("Block shell deletes", Hook(id: "", name: "Block shell deletes", event: "Before a tool runs", action: "Run a command", tools: "shell|bash", agent: "Any agent", source: "Anywhere", target: "check-delete --strict", template: "", timeout: 10, blocks: true, on: true, lastRun: "", outcome: "")),
    ]

    var body: some View {
        SettingsPage(hookID == "new" ? "Add a hook" : "Edit hook") {
            if hookID == "new" {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Start from an example").padding(.leading, 6)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(examples, id: \.0) { example in
                                PillButton(title: example.0) {
                                    withAnimation(Motion.snappy) { hook = example.1 }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
            }
            SettingsGroup {
                FieldRow(title: "Name", text: $hook.name, prompt: "What it does")
                PickRow(title: "Event", selection: $hook.event, options: AdminSample.events) { $0 }
                FieldRow(title: "Tools", text: $hook.tools, prompt: "Blank for every tool. Use | and *")
                PickRow(title: "Agent", selection: $hook.agent, options: ["Any agent", "No agent", "Kip", "Producer", "Scout"]) { $0 }
                PickRow(title: "Source", selection: $hook.source, options: ["Anywhere", "Chats only", "Tasks only", "Agents only"]) { $0 }
            }
            SettingsGroup("Action") {
                PickRow(title: "Do this", selection: $hook.action, options: AdminSample.actions) { $0 }
                switch hook.action {
                case "Post to a web address":
                    FieldRow(title: "Address", text: $hook.target, prompt: "https://", keyboard: .URL)
                    FieldRow(title: "Text", text: $hook.template, prompt: "{time} {summary}")
                case "Add to a vault note":
                    FieldRow(title: "Note", text: $hook.target, prompt: "Folder/Note.md (made if missing)")
                    FieldRow(title: "Line", text: $hook.template, prompt: "{time} {summary}")
                case "Send to a channel":
                    PickRow(title: "Channel", selection: $hook.target, options: ["Telegram", "Discord", "Email"]) { $0 }
                    FieldRow(title: "Message", text: $hook.template, prompt: "{agent}: {card}")
                default:
                    FieldRow(title: "Command", text: $hook.target, prompt: "A command on your desktop")
                    StepperRow(title: "Timeout", value: $hook.timeout, range: 1...120, unit: "s")
                    if hook.event == "Before a tool runs" {
                        ToggleRow(title: "Block on failure", detail: "A failing command stops the tool", isOn: $hook.blocks)
                    }
                }
            }
            Text("Fields you can use: {time} {event} {summary} {agent} {card} {task} {reply} {tool}")
                .font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Palette.inkFaint).padding(.horizontal, 8)
            if let note {
                Text(note).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.danger).padding(.horizontal, 8)
            }
            GoldButton(title: hookID == "new" ? "Add hook" : "Save hook") { submit() }
        }
        .alert("Run this command?", isPresented: $confirmCommand) {
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your desktop will run exactly this:\n\(hook.target)")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let existing = sample.hooks.first(where: { $0.id == hookID }) { hook = existing }
        }
    }

    private func submit() {
        guard !hook.name.trimmingCharacters(in: .whitespaces).isEmpty else { note = "Give the hook a name."; return }
        guard !hook.target.isEmpty else { note = hook.action == "Run a command" ? "Enter the command." : "Fill in where it goes."; return }
        if hook.action == "Run a command" {
            let old = sample.hooks.first { $0.id == hookID }?.target
            if old != hook.target { confirmCommand = true; return }
        }
        save()
    }

    private func save() {
        if hook.action != "Run a command" || hook.event != "Before a tool runs" { hook.blocks = false }
        if hookID == "new" {
            var added = hook
            added = Hook(id: UUID().uuidString, name: hook.name, event: hook.event, action: hook.action, tools: hook.tools, agent: hook.agent, source: hook.source,
                         target: hook.target, template: hook.template, timeout: hook.timeout, blocks: hook.blocks, on: true, lastRun: "Not run yet", outcome: "")
            sample.hooks.append(added)
        } else if let index = sample.hooks.firstIndex(where: { $0.id == hookID }) {
            sample.hooks[index] = hook
        }
        YouStore.shared.say("Hook saved")
        dismiss()
    }
}

// MARK: - System

struct SystemScreen: View {
    @State private var includeSecrets = false
    @State private var backupReady = false
    @State private var preparing = false
    @State private var restoring = false
    @State private var pendingRestore: String?
    @State private var importing = false
    @State private var wipeStep = 0

    var body: some View {
        SettingsPage("Backups and system", subtitle: "Admin. The state of your desktop, and copies of everything.") {
            SettingsGroup("Diagnostics") {
                ValueRow(title: "Vault", value: "Documents/Vault")
                ValueRow(title: "Chats", value: "1,284")
                ValueRow(title: "Notes", value: "312")
                ValueRow(title: "Tasks", value: "27")
                ValueRow(title: "Skills", value: "14")
                ValueRow(title: "Models", value: "5")
                ValueRow(title: "Data size", value: "2.1 GB")
                StatusRow(title: "Discord", status: "Listening")
            }
            SettingsGroup("Back up everything", footer: "Chats, bots, tasks, triggers, connections, skills and settings. The vault is not included.") {
                ToggleRow(title: "Include saved passwords and keys", detail: includeSecrets ? "Anyone with the file can read them. Keep it somewhere private." : nil, isOn: $includeSecrets)
                if backupReady {
                    ShareLink(item: backupSummary, preview: SharePreview("kairos-backup.zip")) {
                        RowLabel(title: "Share the backup", detail: "kairos-backup.zip · 184 MB", symbol: "square.and.arrow.up", tint: Palette.goldText, titleColor: Palette.goldText)
                            .padding(.horizontal, 16).frame(minHeight: 56).contentShape(Rectangle())
                    }
                } else {
                    ActionRow(title: preparing ? "Preparing the backup..." : "Back up now", symbol: "externaldrive", tone: .gold) {
                        guard !preparing else { return }
                        preparing = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation(Motion.snappy) {
                                preparing = false
                                backupReady = true
                            }
                        }
                    }
                }
            }
            SettingsGroup("Restore", footer: "A restore replaces your data the next time Kairos starts. A safety copy is kept and the vault is not touched.") {
                if let pendingRestore {
                    StatusRow(title: "Restore waiting", detail: "\(pendingRestore) · at the next start", status: "Ready", tone: .warn)
                    ActionRow(title: "Cancel pending restore", symbol: "xmark", tone: .danger) {
                        withAnimation(Motion.snappy) { self.pendingRestore = nil }
                        YouStore.shared.say("Restore cancelled")
                    }
                } else {
                    ActionRow(title: "Restore from a backup", symbol: "arrow.counterclockwise") { restoring = true }
                }
                ValueRow(title: "Last restore", value: "October 2 · safety copy kept")
            }
            SettingsGroup("Settings, notes and skills", footer: "A small file you can move to another Kairos.") {
                ShareLink(item: exportText, preview: SharePreview("kairos-export.json")) {
                    RowLabel(title: "Export", symbol: "square.and.arrow.up").padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                }
                ActionRow(title: "Import", symbol: "square.and.arrow.down") { importing = true }
            }
            SettingsGroup(footer: "This affects every user of this Kairos and cannot be undone.") {
                ActionRow(title: "Wipe all chats, notes, tasks and skills", symbol: "trash", tone: .danger) { wipeStep = 1 }
            }
        }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.zip, .data]) { result in
            if case .success(let url) = result {
                withAnimation(Motion.snappy) { pendingRestore = url.lastPathComponent }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success = result {
                YouStore.shared.say("Imported 12 settings, 40 notes and 3 skills")
            }
        }
        .alert("Wipe everything?", isPresented: Binding(get: { wipeStep == 1 }, set: { if !$0 && wipeStep == 1 { wipeStep = 0 } })) {
            Button("Continue", role: .destructive) { wipeStep = 2 }
            Button("Cancel", role: .cancel) { wipeStep = 0 }
        } message: {
            Text("Every chat, note, task and skill for every user goes.")
        }
        .alert("This cannot be undone", isPresented: Binding(get: { wipeStep == 2 }, set: { if !$0 && wipeStep == 2 { wipeStep = 0 } })) {
            Button("Wipe", role: .destructive) {
                wipeStep = 0
                YouStore.shared.say("Wiped. Your vault was not touched.")
            }
            Button("Cancel", role: .cancel) { wipeStep = 0 }
        } message: {
            Text("Make a backup first if you might want any of it.")
        }
    }

    private var backupSummary: String {
        "Kairos backup, sample. Includes chats, bots, tasks, triggers, connections, skills and settings\(includeSecrets ? ", and saved passwords and keys" : "")."
    }

    private var exportText: String {
        "{\n  \"settings\": 12,\n  \"notes\": 40,\n  \"skills\": 3\n}"
    }
}

// MARK: - Shortcuts

struct ShortcutsScreen: View {
    private let groups: [(String, [(String, String)])] = [
        ("Anywhere", [("Search and Jump to", "Ctrl or Cmd + K"), ("Switch to account 1 to 9", "Ctrl or Cmd + Shift + 1 to 9"), ("Quick Entry", "Ctrl or Cmd + Shift + 6"), ("Close a panel", "Esc")]),
        ("Composer", [("Send", "Enter"), ("New line", "Shift + Enter"), ("Commands", "/"), ("Mention a bot", "@"), ("Earlier messages", "Up and Down")]),
        ("Chat", [("Find in chat", "Ctrl or Cmd + F"), ("Next and previous match", "Enter, Shift + Enter"), ("Rename, star or delete", "Right-click")]),
        ("Documents", [("Open a file in the background", "Ctrl or Cmd + click"), ("Resize the document pane", "Left and Right")]),
    ]

    var body: some View {
        SettingsPage("Shortcuts", subtitle: "Keyboard shortcuts work on your desktop. On the phone, use Search and hold the tab bar for Jump to.") {
            ForEach(groups, id: \.0) { group in
                SettingsGroup(group.0) {
                    ForEach(group.1, id: \.0) { item in
                        HStack {
                            Text(item.0).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                            Spacer(minLength: 8)
                            Text(item.1).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(Palette.inkDim)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 50)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            NoteText(text: "On a phone, Return makes a new line. Tap Send to send.")
        }
    }
}

enum AdminDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "admin-users": return AnyView(UsersScreen())
        case "admin-logs": return AnyView(LogsScreen())
        case "admin-runs": return AnyView(RunsScreen())
        case "admin-sandbox": return AnyView(SandboxScreen())
        case "admin-checkpoints": return AnyView(CheckpointsScreen())
        case "admin-hooks": return AnyView(HooksScreen())
        case "admin-hook": return AnyView(HookDetailScreen(hookID: "h2"))
        case "admin-hook-new": return AnyView(HookEditScreen(hookID: "new"))
        case "admin-system": return AnyView(SystemScreen())
        case "admin-shortcuts": return AnyView(ShortcutsScreen())
        default: return nil
        }
    }
}
