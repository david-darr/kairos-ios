import SwiftUI
import UIKit
import UniformTypeIdentifiers

// The Tool Store's detail page for every kind, its sheets (skill manager, GitHub skill installer,
// custom server, install a tab, GitHub sign-in, Build with Kairos) and the Build a tab brief.

// MARK: - Detail

struct StoreItemScreen: View {
    let itemID: String
    var startReview = false
    @Environment(\.dismiss) private var dismiss
    @Bindable private var store = StoreSample.shared
    @State private var checking = false
    @State private var reviewFiles = false
    @State private var scanReview = false
    @State private var editing = false
    @State private var publishing = false
    @State private var confirmRemove = false
    @State private var reaApproval = false
    @State private var bodyDraft = ""

    private var item: StoreItem? { store.item(itemID) }

    var body: some View {
        SettingsPage(item.map(title) ?? "Gone", subtitle: item.map(subtitle)) {
            if let item {
                header(item)
                switch item.kind {
                case .skill: skillPart(item)
                case .tool: toolPart(item)
                case .addon: addonPart(item)
                case .tab: tabPart(item)
                case .automation: automationPart(item)
                case .community: communityPart(item)
                case .design: designPart(item)
                case .shared: sharedPart(item)
                }
            } else {
                EmptyRow(text: "This item was removed.").kCard(radius: 22)
            }
        }
        .sheet(isPresented: $reviewFiles) { TabFilesSheet(itemID: itemID) }
        .sheet(isPresented: $scanReview) { ScanReviewSheet(itemID: itemID) }
        .sheet(isPresented: $publishing) { PublishSheet(itemID: itemID) }
        .sheet(isPresented: $reaApproval) { ReaApprovalSheet(itemID: itemID) }
        .confirmationDialog("Remove \(item?.name ?? "")?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(item?.kind == .addon ? "Its saved data is kept." : item?.kind == .skill ? "This cannot be undone." : "You can add it again from the store.")
        }
        .onAppear {
            bodyDraft = item?.body ?? ""
            if startReview { reviewFiles = true }
        }
    }

    private func title(_ item: StoreItem) -> String { item.name }

    private func subtitle(_ item: StoreItem) -> String {
        item.summary.isEmpty ? item.kind.label : item.summary
    }

    private func header(_ item: StoreItem) -> some View {
        HStack(spacing: 8) {
            Chip(text: item.kind.label, symbol: item.kind.symbol)
            StatusPill(text: item.status.text, tone: item.status.tone)
            if item.kind == .skill || item.kind == .community {
                Text("v\(item.version)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            Spacer()
        }
    }

    // MARK: Kinds

    @ViewBuilder
    private func skillPart(_ item: StoreItem) -> some View {
        if item.unreadable {
            NoteText(text: "This skill can't be read, so no model is offered it until it is fixed or deleted.", symbol: "exclamationmark.triangle")
            SettingsGroup {
                ActionRow(title: "Delete", symbol: "trash", tone: .danger) { confirmRemove = true }
            }
        } else {
            SettingsGroup("Origin") {
                ValueRow(title: "Where it came from", value: item.origin)
                if item.needsApproval {
                    StatusRow(title: "Hidden from models", detail: "Its content scanned as dangerous", status: "Needs approval", tone: .warn)
                }
            }
            if editing {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Body (SKILL.md)").padding(.leading, 6)
                    TextEditor(text: $bodyDraft)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 220)
                        .padding(10)
                        .kCard(radius: 18)
                    HStack {
                        YouPillButton(title: "Save", prominent: true) {
                            store.update(item.id) { $0.body = bodyDraft }
                            withAnimation(Motion.snappy) { editing = false }
                            YouStore.shared.say("Saved \(item.name)")
                        }
                        YouPillButton(title: "Cancel") {
                            bodyDraft = item.body
                            withAnimation(Motion.snappy) { editing = false }
                        }
                    }
                }
            } else {
                Text(item.body.isEmpty ? "This skill has no body yet." : item.body)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kCard(radius: 18)
            }
            SettingsGroup {
                if item.needsApproval {
                    ActionRow(title: "Approve for models", detail: "Later edits need approval again", symbol: "checkmark.shield", tone: .gold) {
                        store.update(item.id) { $0.needsApproval = false }
                        YouStore.shared.say("Models can use \(item.name) now")
                    }
                }
                ActionRow(title: "Manage skill", detail: "Edit its body", symbol: "pencil") {
                    withAnimation(Motion.snappy) { editing = true }
                }
                ActionRow(title: "Share with this Kairos", detail: "Other accounts here can add it", symbol: "person.2") {
                    YouStore.shared.say("Shared with this Kairos")
                }
                ActionRow(title: "Share to the store", detail: "A public pull request on GitHub", symbol: "square.and.arrow.up") { publishing = true }
                if item.origin != "Built into Kairos" {
                    ActionRow(title: "Delete skill", symbol: "trash", tone: .danger) { confirmRemove = true }
                }
            }
        }
    }

    @ViewBuilder
    private func toolPart(_ item: StoreItem) -> some View {
        if item.added {
            SettingsGroup("Health") {
                StatusRow(title: checking ? "Checking..." : item.health, symbol: "waveform.path.ecg",
                          status: item.needsSignIn ? "Not signed in" : item.on ? "Working" : "Turned off",
                          tone: item.needsSignIn ? .warn : item.on ? .ok : .muted)
                ActionRow(title: "Check", symbol: "arrow.clockwise") {
                    checking = true
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        store.update(item.id) { $0.health = "Working · \(item.id == "tl-github" ? 24 : 6) tools · checked just now" }
                        checking = false
                    }
                }
            }
            if !item.heldTools.isEmpty {
                SettingsGroup("Held tools", footer: "\(item.heldTools.count) tools are new or changed. They are held from every model until you accept.") {
                    ForEach(item.heldTools, id: \.self) { tool in
                        HStack {
                            Text(tool).font(.system(size: 15, design: .monospaced)).foregroundStyle(Palette.ink)
                            Spacer()
                            YouPillButton(title: "Accept") {
                                store.update(item.id) { $0.heldTools.removeAll { $0 == tool } }
                            }
                        }
                        .padding(.horizontal, 16).frame(minHeight: 52)
                    }
                    ActionRow(title: "Accept all", symbol: "checkmark", tone: .gold) {
                        store.update(item.id) { $0.heldTools = [] }
                    }
                }
            }
            SettingsGroup {
                if item.needsSignIn {
                    ActionRow(title: "Sign in", detail: "Finish it in the browser on your desktop", symbol: "person.crop.circle", tone: .gold) { signIn(item) }
                }
                YouNavRow(title: "Manage", detail: "Settings, Integrations", symbol: "slider.horizontal.3", to: .integrations)
                ActionRow(title: "Remove", symbol: "trash", tone: .danger) { confirmRemove = true }
            }
        } else {
            NoteText(text: item.id == "tl-rea" ? "REA runs on your desktop through npx and can use its files and apps. You review its tools before any model uses them." : "Choose the servers each chat uses in its Integrations menu.")
            GoldButton(title: item.id == "tl-rea" ? "Review and add" : "Add") {
                if item.id == "tl-rea" { reaApproval = true } else {
                    store.update(item.id) { $0.added = true; $0.health = "Not checked yet" }
                    YouStore.shared.say("\(item.name) added")
                }
            }
        }
    }

    @ViewBuilder
    private func addonPart(_ item: StoreItem) -> some View {
        SettingsGroup(footer: "Installs separately from base Kairos. Disabling or removing it keeps its saved data.") {
            ValueRow(title: "Includes", value: item.files.joined(separator: ", "))
        }
        SettingsGroup {
            if item.added {
                YouToggleRow(title: "Enabled", isOn: Binding(get: { item.on }, set: { on in store.update(item.id) { $0.on = on } }))
                ActionRow(title: "Reinstall", symbol: "arrow.clockwise") { YouStore.shared.say("Reinstalled. Restart Kairos to load its workspace.") }
                ActionRow(title: "Remove add-on", symbol: "trash", tone: .danger) { confirmRemove = true }
            } else {
                ActionRow(title: "Install add-on", symbol: "square.and.arrow.down", tone: .gold) {
                    store.update(item.id) { $0.added = true; $0.on = true }
                    YouStore.shared.say("Add-on installed. Restart Kairos to load its workspace.")
                }
            }
        }
    }

    @ViewBuilder
    private func tabPart(_ item: StoreItem) -> some View {
        if item.needsApproval {
            NoteText(text: "A new tab stays off until you review its files and approve them.", symbol: "checkmark.shield")
        }
        SettingsGroup {
            if !item.prebuilt {
                ActionRow(title: "Review files", detail: "\(item.files.count) files with their SHA-256", symbol: "doc.text") { reviewFiles = true }
            }
            if item.needsApproval {
                ActionRow(title: "Approve", symbol: "checkmark.shield", tone: .gold) {
                    store.update(item.id) { $0.needsApproval = false; $0.on = true }
                    YouStore.shared.say("\(item.name) approved and on")
                }
            } else if item.added {
                YouToggleRow(title: "On", detail: "Off hides it everywhere", isOn: Binding(get: { item.on }, set: { on in store.update(item.id) { $0.on = on } }))
                YouNavRow(title: "Open \(item.name)", symbol: item.symbol, to: .addedTab(item.name))
            }
            if item.prebuilt && !item.added {
                ActionRow(title: "Add", symbol: "plus", tone: .gold) {
                    store.update(item.id) { $0.added = true; $0.on = true }
                    YouStore.shared.say("\(item.name) added. It is in Jump to.")
                }
            }
            if !item.prebuilt {
                ShareLink(item: "\(item.name).kairostab (sample package)", preview: SharePreview("\(item.name).kairostab")) {
                    RowLabel(title: "Export", symbol: "square.and.arrow.up").padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                }
                ActionRow(title: "Share to the store", symbol: "globe") { publishing = true }
            }
            if item.added {
                ActionRow(title: "Remove", symbol: "trash", tone: .danger) { confirmRemove = true }
            }
        }
    }

    private func automationPart(_ item: StoreItem) -> some View {
        SettingsGroup(footer: "Added automations start turned off. Choose delivery and a model in Tasks.") {
            if item.added {
                YouToggleRow(title: "On", isOn: Binding(get: { item.on }, set: { on in store.update(item.id) { $0.on = on } }))
                ActionRow(title: "Remove", symbol: "trash", tone: .danger) { confirmRemove = true }
            } else {
                ActionRow(title: "Add", symbol: "plus", tone: .gold) {
                    store.update(item.id) { $0.added = true; $0.on = false }
                    YouStore.shared.say("Added, turned off. Set it up in Tasks.")
                }
            }
        }
    }

    @ViewBuilder
    private func communityPart(_ item: StoreItem) -> some View {
        SettingsGroup {
            ValueRow(title: "By", value: "@\(item.author)")
            ValueRow(title: "Kind", value: item.origin)
            ValueRow(title: "Version", value: item.version)
        }
        if item.revoked {
            NoteText(text: "Withdrawn by the store: it stopped meeting the review rules. It stays turned off.", symbol: "exclamationmark.triangle")
        }
        SettingsGroup {
            if !item.added {
                ActionRow(title: "Install", detail: "It is scanned first", symbol: "square.and.arrow.down", tone: .gold) { scanReview = true }
            } else if item.updateAvailable {
                ActionRow(title: "Update to 1.5.0", symbol: "arrow.down.circle", tone: .gold) {
                    store.update(item.id) { $0.updateAvailable = false; $0.version = "1.5.0" }
                    YouStore.shared.say("Updated \(item.name)")
                }
            } else if item.revoked {
                ActionRow(title: "Turn back on", detail: "Only if you trust it anyway", symbol: "power") {
                    store.update(item.id) { $0.revoked = false }
                }
            }
            if item.added {
                ActionRow(title: "Remove", symbol: "trash", tone: .danger) { confirmRemove = true }
            }
        }
    }

    @ViewBuilder
    private func designPart(_ item: StoreItem) -> some View {
        HStack(spacing: 8) {
            ForEach([Palette.ground, Palette.surface2, Palette.ink, Palette.gold, Palette.success], id: \.self) { color in
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color)
                    .frame(height: 54)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            }
        }
        SettingsGroup {
            ValueRow(title: "Who sees it", value: item.origin)
            ActionRow(title: item.on ? "Stop using as default" : "Use as default", symbol: "star") {
                store.update(item.id) { $0.on.toggle() }
                YouStore.shared.say(item.on ? "New designs pick their own look again" : "New designs start in \(item.name)")
            }
            if item.id != "ds-kairos" {
                ActionRow(title: "Share with everyone", symbol: "person.2") { YouStore.shared.say("Shared with everyone") }
                ActionRow(title: "Remove", detail: "Designs using it fall back to Kairos", symbol: "trash", tone: .danger) { confirmRemove = true }
            }
        }
    }

    private func sharedPart(_ item: StoreItem) -> some View {
        SettingsGroup {
            ValueRow(title: "From", value: item.origin)
            ActionRow(title: item.added ? "Added" : "Add to my skills", symbol: "plus", tone: .gold) {
                store.update(item.id) { $0.added = true }
            }
        }
    }

    private func signIn(_ item: StoreItem) {
        YouStore.shared.say("Waiting for sign-in on your desktop...")
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            store.update(item.id) { $0.needsSignIn = false; $0.health = "Working · 9 tools · checked just now" }
            YouStore.shared.say("Signed in to \(item.name).")
        }
    }

    private func remove() {
        guard let item else { return }
        if item.prebuilt || item.kind == .tool || item.kind == .addon || item.kind == .automation || item.kind == .community {
            store.update(item.id) { $0.added = false }
            YouStore.shared.say("Removed \(item.name)")
        } else {
            store.items.removeAll { $0.id == item.id }
            YouStore.shared.say("Deleted \(item.name)")
            dismiss()
        }
    }
}

// MARK: - Sheets used by the detail

private struct TabFilesSheet: View {
    let itemID: String
    @Environment(\.dismiss) private var dismiss
    private let store = StoreSample.shared

    var body: some View {
        FittedSheet(estimate: 460) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review files").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink).padding(.top, 30)
                Text("The exact files this tab runs. Approve only what you expect.")
                    .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                VStack(spacing: 0) {
                    ForEach(Array((store.item(itemID)?.files ?? []).enumerated()), id: \.offset) { index, file in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file).font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink)
                            Text(fakeHash(file)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Palette.inkFaint).lineLimit(1).truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
                    }
                }
                .kCard(radius: 18)
                if store.item(itemID)?.needsApproval == true {
                    GoldButton(title: "Approve") {
                        store.update(itemID) { $0.needsApproval = false; $0.on = true }
                        YouStore.shared.say("Approved and on")
                        dismiss()
                    }
                }
                QuietButton(title: "Close") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
    }

    private func fakeHash(_ name: String) -> String {
        let seed = name.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        return (0..<8).map { String(format: "%08lx", (seed &* ($0 + 3) &* 2654435761) & 0xFFFFFFFF) }.joined()
    }
}

private struct ScanReviewSheet: View {
    let itemID: String
    @Environment(\.dismiss) private var dismiss
    @State private var scanning = true
    private let store = StoreSample.shared

    var body: some View {
        FittedSheet(estimate: 420) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review this \(store.item(itemID)?.origin.components(separatedBy: " · ").last ?? "item")").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink).padding(.top, 30)
                if scanning {
                    HStack(spacing: 10) {
                        ProgressView().tint(Palette.gold)
                        Text("Downloading and scanning...").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    }
                } else {
                    SettingsGroup("Scan report") {
                        StatusRow(title: "Files", detail: "4 files, 18 kB", status: "Checked")
                        StatusRow(title: "Network use", detail: "Reads one public address", status: "Note", tone: .warn)
                        StatusRow(title: "Shell commands", detail: "None found", status: "Clear")
                    }
                    GoldButton(title: "Install anyway") {
                        store.update(itemID) { $0.added = true }
                        YouStore.shared.say(store.item(itemID)?.origin.hasSuffix("tab") == true ? "Installed. Review and approve its files in Yours." : "Installed")
                        dismiss()
                    }
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(Motion.snappy) { scanning = false }
        }
    }
}

private struct ReaApprovalSheet: View {
    let itemID: String
    @Environment(\.dismiss) private var dismiss
    private let store = StoreSample.shared

    var body: some View {
        FittedSheet(estimate: 480) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Download and add REA?").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink).padding(.top, 30)
                SettingsGroup {
                    ValueRow(title: "Node.js", value: "22.4")
                    ValueRow(title: "npm", value: "10.8")
                    RowLabel(title: "Runs on your desktop", detail: "Through npx. It can open files and apps there. It is separate software from Kairos.")
                        .padding(.horizontal, 16).padding(.vertical, 12)
                }
                NoteText(text: "You review its tools before any model can use them.")
                GoldButton(title: "Download and add") {
                    store.update(itemID) { $0.added = true; $0.heldTools = ["open_app", "read_file", "click"] }
                    YouStore.shared.say("REA added. Accept its tools to use them.")
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
    }
}

private struct PublishSheet: View {
    let itemID: String
    @Environment(\.dismiss) private var dismiss
    @State private var slug = ""
    @State private var name = ""
    @State private var summary = ""
    @State private var version = "1.0.0"
    @State private var previewed = false
    @State private var consent = false
    @State private var stage = "edit"
    private let store = StoreSample.shared

    private var valid: Bool {
        !slug.isEmpty && slug == slug.lowercased() && !slug.contains(" ") && !name.isEmpty && !summary.isEmpty
            && version.split(separator: ".").count == 3
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Share to the store").font(KFont.ui(22, .semibold, relativeTo: .title2)).foregroundStyle(Palette.ink).padding(.top, 30)
                    Text("Submissions are public on GitHub and need review and a merge before they appear in the store.")
                        .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                    if stage == "done" {
                        StatusRow(title: "Pull request #215", detail: "Open on GitHub", status: "Opened")
                            .kCard(radius: 20)
                        GoldButton(title: "Done") { dismiss() }
                    } else {
                        SettingsGroup {
                            FieldRow(title: "Slug", text: $slug, prompt: "lowercase-name")
                            FieldRow(title: "Name", text: $name, prompt: "Name")
                            FieldRow(title: "Description", text: $summary, prompt: "One line")
                            FieldRow(title: "Version", text: $version, prompt: "1.0.0")
                        }
                        .onChange(of: slug) { previewed = false; consent = false }
                        .onChange(of: version) { previewed = false; consent = false }
                        if previewed {
                            SettingsGroup("Exactly these files go up") {
                                ValueRow(title: "\(slug)/SKILL.md", value: "2 kB")
                                ValueRow(title: "\(slug)/store.json", value: "1 kB")
                            }
                            SettingsGroup {
                                YouToggleRow(title: "I understand it will be public on GitHub under the MIT licence", isOn: $consent)
                            }
                        }
                        if !previewed {
                            GoldButton(title: "Preview files") {
                                guard valid else { YouStore.shared.say("Fill in a lowercase slug, a name, a description and a version like 1.0.0."); return }
                                withAnimation(Motion.snappy) { previewed = true }
                            }
                        } else {
                            GoldButton(title: stage == "publishing" ? "Opening your pull request..." : "Open pull request") {
                                guard consent, stage == "edit" else { return }
                                stage = "publishing"
                                Task {
                                    try? await Task.sleep(for: .seconds(1.4))
                                    store.submissions.insert(StoreSubmission(id: 215, title: "Add \(slug) \(version)", state: "Open"), at: 0)
                                    withAnimation(Motion.snappy) { stage = "done" }
                                }
                            }
                            .opacity(consent ? 1 : 0.5)
                        }
                        QuietButton(title: "Cancel") { dismiss() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .kSheet()
        .onAppear {
            let item = store.item(itemID)
            slug = item?.name.lowercased().replacingOccurrences(of: " ", with: "-") ?? ""
            name = item?.name ?? ""
            summary = item?.summary ?? ""
        }
    }
}

// MARK: - Sheets from the store's + menu

struct StoreSheetView: View {
    let which: StoreSheet

    var body: some View {
        switch which {
        case .skillManager: SkillManagerSheet()
        case .customServer: CustomServerSheet()
        case .githubSkill: GitHubSkillSheet()
        case .installTab: InstallTabSheet()
        case .github: GitHubSignInSheet()
        case .brief: BuilderBriefSheet()
        }
    }
}

private struct SkillManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var summary = ""
    @State private var importing = false
    @State private var importReview: String?
    @Bindable private var store = StoreSample.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Manage skills").font(KFont.ui(22, .semibold, relativeTo: .title2)).foregroundStyle(Palette.ink).padding(.top, 30)
                    SettingsGroup("New skill") {
                        FieldRow(title: "Skill name", text: $name, prompt: "Skill name...")
                        FieldRow(title: "One-line description", text: $summary, prompt: "One-line description...")
                        ActionRow(title: "Create", symbol: "plus", tone: .gold) {
                            let clean = name.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
                            guard !clean.isEmpty else { return }
                            store.items.insert(StoreItem(id: "sk-\(UUID().uuidString.prefix(6))", kind: .skill, name: clean, summary: summary, origin: "Written in Kairos", added: true, body: "# \(name)\n\n"), at: 0)
                            name = ""
                            summary = ""
                            YouStore.shared.say("Created \(clean)")
                        }
                        ActionRow(title: "Import from Files", detail: ".md or .txt", symbol: "doc.badge.plus") { importing = true }
                    }
                    if let importReview {
                        SettingsGroup("\(importReview) needs a look before importing") {
                            StatusRow(title: "Shell commands", detail: "One command that deletes files", status: "Warning", tone: .bad)
                            ActionRow(title: "Import anyway", symbol: "exclamationmark.triangle", tone: .danger) {
                                store.items.insert(StoreItem(id: "sk-\(UUID().uuidString.prefix(6))", kind: .skill, name: importReview.replacingOccurrences(of: ".md", with: "").lowercased(), summary: "Imported from a file", origin: "Imported skill", added: true, needsApproval: true), at: 0)
                                self.importReview = nil
                                YouStore.shared.say("Imported \(importReview)")
                            }
                            ActionRow(title: "Cancel", symbol: "xmark") { self.importReview = nil }
                        }
                    }
                    SettingsGroup("Your skills") {
                        ForEach(store.items.filter { $0.kind == .skill }) { item in
                            StoreRow(item: item)
                        }
                    }
                    QuietButton(title: "Close") { dismiss() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .toolbar(.hidden, for: .navigationBar)
            .youDestinations()
        }
        .kSheet()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText]) { result in
            if case .success(let url) = result { importReview = url.lastPathComponent }
        }
    }
}

private struct CustomServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var auth = "No sign-in"
    @State private var token = ""
    @State private var note: String?
    @State private var adding = false
    private let store = StoreSample.shared

    var body: some View {
        FittedSheet(estimate: 520) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add a custom MCP server").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink).padding(.top, 30)
                SettingsGroup {
                    FieldRow(title: "Server name", text: $name, prompt: "Name")
                    FieldRow(title: "MCP server URL", text: $address, prompt: "https://", keyboard: .URL)
                    PickRow(title: "Sign-in", selection: $auth, options: ["No sign-in", "OAuth sign-in", "Bearer token"]) { $0 }
                    if auth == "Bearer token" {
                        FieldRow(title: "Token", text: $token, prompt: "Paste the token", secure: true)
                    }
                }
                YouNavRow(title: "Advanced connection settings", symbol: "slider.horizontal.3", to: .integrations).kCard(radius: 22)
                if let note { Text(note).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.danger) }
                GoldButton(title: adding ? "Adding server..." : "Add server") { add() }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
    }

    private func add() {
        guard !name.isEmpty else { note = "Name the server."; return }
        guard let url = URL(string: address), let scheme = url.scheme, ["http", "https"].contains(scheme), url.user == nil, url.fragment == nil else {
            note = "Use an http or https address, with no sign-in details or # in it."
            return
        }
        guard !store.items.contains(where: { $0.kind == .tool && $0.name.lowercased() == name.lowercased() }) else {
            note = "This server is already added."
            return
        }
        adding = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            store.items.append(StoreItem(id: "tl-\(UUID().uuidString.prefix(6))", kind: .tool, name: name, summary: address, origin: "Custom MCP server", added: true, needsSignIn: auth == "OAuth sign-in"))
            YouStore.shared.say("\(name) added")
            dismiss()
        }
    }
}

private struct GitHubSkillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var stage = "edit"
    private let store = StoreSample.shared

    var body: some View {
        FittedSheet(estimate: 440) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Install a skill from GitHub").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink).padding(.top, 30)
                Text("One SKILL.md file. Files beside it are not brought in, and it is scanned first.")
                    .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                SettingsGroup {
                    FieldRow(title: "GitHub SKILL.md link", text: $link, prompt: "https://github.com/...", keyboard: .URL)
                }
                switch stage {
                case "scanning":
                    HStack(spacing: 10) {
                        ProgressView().tint(Palette.gold)
                        Text("Downloading and scanning...").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    }
                case "review":
                    SettingsGroup("Review this skill") {
                        StatusRow(title: "Scan", detail: "No risky commands found", status: "Clear")
                        ValueRow(title: "SHA-256", value: "4be1…9c02")
                    }
                    GoldButton(title: "Install skill") {
                        let slug = link.split(separator: "/").dropLast().last.map(String.init) ?? "github-skill"
                        store.items.insert(StoreItem(id: "sk-\(UUID().uuidString.prefix(6))", kind: .skill, name: slug.lowercased(), summary: "Installed from GitHub", origin: "GitHub", added: true, body: "# \(slug)\n\nInstalled from GitHub."), at: 0)
                        YouStore.shared.say("Installed \(slug.lowercased())")
                        dismiss()
                    }
                default:
                    GoldButton(title: "Check skill") {
                        guard link.hasPrefix("https://") else { YouStore.shared.say("Paste the SKILL.md link first."); return }
                        stage = "scanning"
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            withAnimation(Motion.snappy) { stage = "review" }
                        }
                    }
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
    }
}

private struct InstallTabSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var replace = false
    @State private var picking = false
    @State private var scanning = false
    private let store = StoreSample.shared

    var body: some View {
        FittedSheet(estimate: 480) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Install a tab").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink).padding(.top, 30)
                SettingsGroup {
                    ActionRow(title: "Choose a .kairostab file", symbol: "doc.badge.plus") { picking = true }
                    FieldRow(title: "Or a GitHub folder", text: $link, prompt: "https://github.com/.../my-tab", keyboard: .URL)
                    YouToggleRow(title: "Replace an existing tab of mine", detail: replace ? "Its approval is revoked until you review it again" : nil, isOn: $replace)
                }
                if scanning {
                    HStack(spacing: 10) {
                        ProgressView().tint(Palette.gold)
                        Text("Downloading and scanning...").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    }
                }
                GoldButton(title: "Install GitHub folder") {
                    guard link.hasPrefix("https://") else { YouStore.shared.say("Paste the folder link first."); return }
                    install(name: link.split(separator: "/").last.map(String.init) ?? "New tab")
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "kairostab") ?? .data, .data]) { result in
            if case .success(let url) = result { install(name: url.deletingPathExtension().lastPathComponent) }
        }
    }

    private func install(name: String) {
        scanning = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            store.items.append(StoreItem(id: "tb-\(UUID().uuidString.prefix(6))", kind: .tab, name: name.capitalized, summary: "Installed by you", origin: "Yours", added: true, needsApproval: true, files: ["tab.json", "view.html"], symbol: "square.grid.2x2"))
            YouStore.shared.say("Installed. Review and approve its files in Yours.")
            dismiss()
        }
    }
}

private struct GitHubSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var waiting = false
    private let store = StoreSample.shared
    private let code = "KRS4-7QPD"

    var body: some View {
        FittedSheet(estimate: 420) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sign in with GitHub").font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink).padding(.top, 30)
                Text("Enter this code at github.com/login/device, then come back.")
                    .font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.inkDim)
                HStack {
                    Text(code).font(.system(size: 30, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.ink)
                    Spacer()
                    YouPillButton(title: "Copy code", symbol: "doc.on.doc") {
                        UIPasteboard.general.string = code
                        YouStore.shared.say("Code copied")
                    }
                }
                .padding(16)
                .kCard(radius: 20, raised: true)
                if waiting {
                    HStack(spacing: 10) {
                        ProgressView().tint(Palette.gold)
                        Text("Waiting for GitHub...").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    }
                }
                GoldButton(title: "I entered the code") {
                    waiting = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        store.githubUser = "shop-builder"
                        YouStore.shared.say("Signed in to GitHub")
                        dismiss()
                    }
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
    }
}

private struct BuilderBriefSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "Skill"
    @State private var what = ""
    @State private var when = ""
    @State private var done = ""
    @State private var model = "Claude Sonnet"
    @State private var starting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("\(kind) brief").font(KFont.ui(22, .semibold, relativeTo: .title2)).foregroundStyle(Palette.ink).padding(.top, 30)
                    GlassSwitch(items: ["Skill", "Tool", "Automation"], selection: $kind) { $0 }
                    SettingsGroup {
                        FieldRow(title: "What should it do?", text: $what, prompt: "Check three shops for a part")
                        FieldRow(title: "When is it used?", text: $when, prompt: "When I ask about stock")
                        FieldRow(title: "What does done look like?", text: $done, prompt: "A table with prices")
                        PickRow(title: "Model to build it", selection: $model, options: ["Claude Sonnet", "Claude Opus", "GPT-6.1 Sol"]) { $0 }
                    }
                    GoldButton(title: starting ? "Starting..." : "Build with Kairos") {
                        guard !what.isEmpty, !when.isEmpty, !done.isEmpty else {
                            YouStore.shared.say("Fill in the three questions first.")
                            return
                        }
                        starting = true
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            YouStore.shared.say("Kairos is building it in a new chat")
                            dismiss()
                        }
                    }
                    QuietButton(title: "Cancel") { dismiss() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .kSheet()
    }
}

// MARK: - Build a tab

struct BuildTabScreen: View {
    @State private var name = ""
    @State private var icon = ""
    @State private var purpose = ""
    @State private var sources: Set<String> = ["Calendar"]
    @State private var other = ""
    @State private var savesData = false
    @State private var fields = ""
    @State private var example = ""
    @State private var look = ""
    @State private var model = "Claude Sonnet"
    @State private var starting = false

    var body: some View {
        SettingsPage("Build a tab", subtitle: "Describe it, and Kairos builds it in a new chat. You approve its files before it turns on.") {
            SettingsGroup {
                FieldRow(title: "Tab name", text: $name, prompt: "Stock count")
                FieldRow(title: "Icon idea", text: $icon, prompt: "A box")
                FieldRow(title: "What should this tab do?", text: $purpose, prompt: "Count shelves and flag low stock")
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Where its data comes from").padding(.leading, 6)
                HStack(spacing: 8) {
                    ForEach(["Gmail", "Calendar", "Canvas or School", "Custom API"], id: \.self) { source in
                        let on = sources.contains(source)
                        Button {
                            Haptics.select()
                            if on { sources.remove(source) } else { sources.insert(source) }
                        } label: {
                            Text(source).font(KFont.ui(13.5, on ? .semibold : .regular, relativeTo: .footnote))
                                .foregroundStyle(on ? Palette.onGold : Palette.inkDim)
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .padding(.horizontal, 10).frame(minHeight: 44)
                                .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            SettingsGroup {
                FieldRow(title: "Another source", text: $other, prompt: "Optional")
                YouToggleRow(title: "This tab saves its own data", isOn: $savesData)
                if savesData {
                    FieldRow(title: "What it saves", text: $fields, prompt: "Item, shelf, count, date")
                }
                FieldRow(title: "Example use", text: $example, prompt: "On Monday I count the back room")
                FieldRow(title: "Look and feel", text: $look, prompt: "Big numbers, calm colours")
                PickRow(title: "Model to build it", selection: $model, options: ["Claude Sonnet", "Claude Opus", "GPT-6.1 Sol"]) { $0 }
            }
            GoldButton(title: starting ? "Starting..." : "Build my tab") {
                guard !name.isEmpty, !purpose.isEmpty else {
                    YouStore.shared.say("Tab name and what it should do are both required.")
                    return
                }
                starting = true
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    starting = false
                    YouStore.shared.say("Kairos is building \(name) in a new chat")
                }
            }
        }
    }
}

enum StoreDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "store": return AnyView(ToolStoreScreen())
        case "store-tabs": return AnyView(ToolStoreScreen(startCategory: .tabs))
        case "store-skill": return AnyView(StoreItemScreen(itemID: "sk-price"))
        case "store-tool": return AnyView(StoreItemScreen(itemID: "tl-github"))
        case "store-addon": return AnyView(StoreItemScreen(itemID: "ad-roblox"))
        case "store-tab-review": return AnyView(StoreItemScreen(itemID: "tb-stock", startReview: true))
        case "store-community": return AnyView(StoreItemScreen(itemID: "cm-invoice"))
        case "store-github": return AnyView(ToolStoreScreen(startSheet: .github))
        case "store-manage": return AnyView(ToolStoreScreen(startSheet: .skillManager))
        case "store-build-tab": return AnyView(BuildTabScreen())
        case "store-add-tab": return AnyView(AddTabScreen())
        case "store-added-crm": return AnyView(AddedTabScreen(title: "CRM"))
        case "store-added-board": return AnyView(AddedTabScreen(title: "Team board"))
        default: return nil
        }
    }
}
