import SwiftUI
import UniformTypeIdentifiers

/// The draft a ready-made bot starts from.
extension ReadyBot {
    var draft: NewBotDraft {
        var d = NewBotDraft()
        d.name = name
        d.job = role
        d.introduction = blurb
        d.colorHex = colorHex
        d.shape = shape
        d.accessory = accessory
        d.routines = (0..<routines).map { index in
            var routine = Routine(botID: "", name: index == 0 ? "Daily check" : "Weekly summary", instructions: "Check for anything new and tell me what matters.", mode: .daily, hour: 9)
            routine.on = false
            return routine
        }
        return d
    }
}

/// A sheet item wrapper so a draft can drive `.sheet(item:)`.
struct DraftBox: Identifiable {
    let id = UUID()
    var draft: NewBotDraft
    var advanced = false
}

/// Make a new bot: a blank start, ready-made bots, presets, packages and archived bots.
struct BotMakerScreen: View {
    var openCreate: DraftBox? = nil
    let store = BotsStore.shared
    @Environment(AppRouter.self) private var router: AppRouter?
    @State private var creating: DraftBox?
    @State private var deletingPreset: String?
    @State private var defaults = false
    @State private var goto: BotsRoute?
    @State private var started = false

    var body: some View {
        BotsPage("Make a bot") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Every bot is a Kip with a job.").font(KFont.display(30)).foregroundStyle(Palette.ink)
                Text("Start blank, or from a bot that already knows the work.").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
            }

            HStack(spacing: 10) {
                startCard("Start blank", "Name, job and look", "plus") { creating = DraftBox(draft: NewBotDraft()) }
                startCard("Every option", "Soul, model, routines", "slider.horizontal.3") { creating = DraftBox(draft: NewBotDraft(), advanced: true) }
            }

            readyRow

            if !store.presets.isEmpty { presets }

            VStack(spacing: 0) {
                NavigationLink(value: BotsRoute.packages) { NavRow(title: "Import or share a package", symbol: "shippingbox", detail: "Whole teams, with their routines and skills") }
                if !store.archived.isEmpty {
                    RowLine(inset: 54)
                    NavigationLink(value: BotsRoute.archived) { NavRow(title: "Archived bots", symbol: "archivebox", value: "\(store.archived.count)") }
                }
                RowLine(inset: 54)
                Button { defaults = true } label: { NavRow(title: "New-bot defaults", symbol: "gearshape", detail: "What every new bot starts with") }
                RowLine(inset: 54)
                NavigationLink(value: BotsRoute.allBots) { NavRow(title: "All bots", symbol: "person.3", value: "\(store.bots.count)") }
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .kCard(radius: 20)
        }
        .navigationDestination(item: $goto) { BotsDestination(route: $0) }
        .sheet(item: $creating) { box in
            BotCreateSheet(start: box.draft, advanced: box.advanced) { id in open(id) }
        }
        .sheet(isPresented: Binding(get: { deletingPreset != nil }, set: { if !$0 { deletingPreset = nil } })) {
            ConfirmSheet(title: "Delete the \(deletingPreset ?? "") preset?", detail: "Bots already made from it are not changed.", confirm: "Delete preset") {
                store.presets.removeAll { $0 == deletingPreset }
            }
        }
        .sheet(isPresented: $defaults) { DefaultsSheet() }
        .onAppear {
            guard !started else { return }
            started = true
            creating = openCreate
        }
    }

    private var readyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Ready-made bots")
                NavigationLink(value: BotsRoute.readyMade) {
                    Text("See all").font(KFont.ui(14, .medium)).foregroundStyle(Palette.goldText).frame(minHeight: 32)
                }
            }
            .padding(.horizontal, 4)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(store.readyBots.enumerated()), id: \.element.id) { index, ready in
                        Button {
                            Haptics.tap()
                            creating = DraftBox(draft: ready.draft)
                        } label: {
                            VStack(spacing: 6) {
                                Mascot(shape: ready.shape, colorHex: ready.colorHex, accessory: ready.accessory, size: 72, stage: Palette.surfaceSolid)
                                Text(ready.name).font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                                Text(ready.role).font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint).lineLimit(2).multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 8)
                            .frame(width: 132, height: 168)
                            .kCard(radius: 22)
                        }
                        .buttonStyle(PressStyle(scale: 0.95))
                        .arrives(index)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private var presets: some View {
        BotsSection(title: "Your presets") {
            ForEach(Array(store.presets.enumerated()), id: \.offset) { index, preset in
                if index > 0 { RowLine(inset: 54) }
                HStack(spacing: 12) {
                    Button {
                        var d = NewBotDraft()
                        d.job = preset
                        creating = DraftBox(draft: d)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.on.square").foregroundStyle(Palette.goldText).frame(width: 26)
                            Text(preset).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                            Spacer()
                        }
                        .frame(minHeight: 52).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                    Button { deletingPreset = preset } label: {
                        Image(systemName: "trash").foregroundStyle(Palette.danger).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Delete the \(preset) preset")
                }
                .padding(.leading, 16).padding(.trailing, 4)
            }
        }
    }

    private func open(_ id: String) {
        if let router { router.push(.bot(id), on: .home) } else { goto = .botPage(id) }
    }

    private func startCard(_ title: String, _ detail: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.onGold)
                    .frame(width: 40, height: 40).background(Palette.gold, in: Circle())
                Text(title).font(KFont.ui(16.5, .semibold)).foregroundStyle(Palette.ink)
                Text(detail).font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .kCard(radius: 22, raised: true)
        }
        .buttonStyle(PressStyle(scale: 0.96))
    }
}

/// What every new bot starts with.
struct DefaultsSheet: View {
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var model = "Claude Sonnet"
    @State private var effort: Effort = .high
    @State private var approval = "Ask first"
    @State private var tell = "In the app only"
    @State private var clearing = false

    var body: some View {
        FittedSheet(estimate: 560) {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: "New-bot defaults", detail: "Every new bot starts with these. A name is never a default.")
                BotsSection {
                    MenuRow(title: "Model", options: BotsSample.models.map(\.name), selection: $model)
                    RowLine()
                    MenuRow(title: "Approval", options: ["Ask first", "Allow edits", "Auto"], selection: $approval)
                    RowLine()
                    MenuRow(title: "Tell me on", options: BotsSample.channels, selection: $tell)
                }
                GoldSegmented(items: Effort.allCases, selection: $effort) { $0.title }
                GoldButton(title: "Save defaults") {
                    store.say("Defaults saved")
                    dismiss()
                }
                PillButton(title: "Clear defaults", look: .danger, wide: true) { clearing = true }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $clearing) {
            ConfirmSheet(title: "Clear the defaults?", detail: "New bots will start blank again. Bots you already made are not changed.", confirm: "Clear defaults") {
                model = "Claude Sonnet"; effort = .high; approval = "Ask first"; tell = "In the app only"
                store.say("Defaults cleared")
            }
        }
    }
}

// MARK: - Ready-made bots

struct ReadyMadeScreen: View {
    let store = BotsStore.shared
    @Environment(AppRouter.self) private var router: AppRouter?
    @State private var category = "All"
    @State private var creating: DraftBox?
    @State private var goto: BotsRoute?

    var body: some View {
        let categories = ["All"] + Array(Set(store.readyBots.map(\.category))).sorted()
        let shown = store.readyBots.filter { category == "All" || $0.category == category }
        BotsPage("Ready-made bots", subtitle: "\(store.readyBots.count) bots") {
            ChipPicker(items: categories, isOn: { $0 == category }, title: { $0 }) { category = $0 }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, ready in
                readyCard(ready).arrives(index)
            }
        }
        .navigationDestination(item: $goto) { BotsDestination(route: $0) }
        .sheet(item: $creating) { box in
            BotCreateSheet(start: box.draft) { id in
                if let router { router.push(.bot(id), on: .home) } else { goto = .botPage(id) }
            }
        }
    }

    private func readyCard(_ ready: ReadyBot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Mascot(shape: ready.shape, colorHex: ready.colorHex, accessory: ready.accessory, size: 70, stage: Palette.surfaceSolid)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ready.name).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
                    Text(ready.role).font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                }
            }
            Text(ready.blurb).font(KFont.ui(15)).foregroundStyle(Palette.ink)
            Text("Try asking: \"\(ready.tryAsking)\"").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
            if ready.routines > 0 {
                Label(ready.routines == 1 ? "Suggests a routine, off until you turn it on" : "Suggests \(ready.routines) routines, off until you turn them on", systemImage: "clock")
                    .font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
            }
            PillButton(title: "Add \(ready.name)", symbol: "plus", look: .filled, wide: true) { creating = DraftBox(draft: ready.draft) }
        }
        .padding(16)
        .kCard(radius: 22)
    }
}

// MARK: - Archived bots

struct ArchivedBotsScreen: View {
    let store = BotsStore.shared
    @State private var deleting: Bot?
    @State private var deletingAll = false

    var body: some View {
        BotsPage("Archived bots", subtitle: "\(store.archived.count) archived") {
            if store.archived.isEmpty {
                EmptyNote(text: "Nothing is archived.", symbol: "archivebox").kCard(radius: 20)
            } else {
                HintLine(text: "Archived bots are hidden. Their routines keep running until you delete them.")
                VStack(spacing: 0) {
                    ForEach(Array(store.archived.enumerated()), id: \.element.id) { index, bot in
                        if index > 0 { RowLine(inset: 70) }
                        row(bot)
                    }
                }
                .kCard(radius: 20)
                HStack(spacing: 10) {
                    PillButton(title: "Restore all", wide: true) {
                        withAnimation(Motion.snappy) { for bot in store.archived { store.restore(bot.id) } }
                        store.say("Everyone is back")
                    }
                    PillButton(title: "Delete all", look: .danger, wide: true) { deletingAll = true }
                }
            }
        }
        .sheet(item: $deleting) { bot in
            ConfirmSheet(title: "Delete \(bot.name)?", detail: "This removes its routines and notes. Its conversations stay in Chats.", confirm: "Delete bot") {
                withAnimation(Motion.snappy) { store.deleteArchived(bot.id) }
            }
        }
        .sheet(isPresented: $deletingAll) {
            ConfirmSheet(title: "Delete all \(store.archived.count) archived bots?", detail: "This cannot be undone. Their conversations stay in Chats.", confirm: "Delete all") {
                withAnimation(Motion.snappy) { store.archived.removeAll() }
                store.say("The archive is empty")
            }
        }
    }

    private func row(_ bot: Bot) -> some View {
        HStack(spacing: 12) {
            BotFace(bot: bot, size: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text(bot.name).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                Text(bot.role).font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
            }
            Spacer()
            PillButton(title: "Restore", look: .filled) {
                Haptics.success()
                withAnimation(Motion.snappy) { store.restore(bot.id) }
            }
            Button { deleting = bot } label: {
                Image(systemName: "trash").foregroundStyle(Palette.danger).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Delete \(bot.name)")
        }
        .padding(.leading, 14).padding(.trailing, 4).frame(minHeight: 64)
    }
}

// MARK: - Packages

struct PackagesScreen: View {
    var startTab = "Explore"
    var preview = false
    let store = BotsStore.shared
    @State private var tab = "Explore"
    @State private var previewing = false
    @State private var picking = false
    @State private var sharing: Set<String> = ["producer", "scout", "quill"]
    @State private var pausedRoutines = true
    @State private var theirTeams = true
    @State private var theirRooms = true
    @State private var exported = false
    @State private var started = false

    var body: some View {
        BotsPage("Packages") {
            HStack {
                Spacer()
                GlassSwitch(items: ["Explore", "Import", "Share"], selection: $tab) { $0 }.fixedSize()
                Spacer()
            }
            if tab == "Import" { importTab } else if tab == "Share" { shareTab } else { exploreTab }
        }
        .sheet(isPresented: $previewing) { PackagePreviewSheet() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json, .plainText]) { result in
            if case .success = result { previewing = true } else { store.say("Choose a JSON or Markdown package.") }
        }
        .onAppear {
            guard !started else { return }
            started = true
            tab = startTab
            previewing = preview
        }
    }

    private var exploreTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A team for your work").font(KFont.display(28)).foregroundStyle(Palette.ink)
            teamCard("Content team", "Plans, researches and writes a short video a day.", ["producer", "scout", "quill"])
            teamCard("Shop office", "Files receipts, tracks bills and reminds you.", ["ledger", "posy"])
        }
    }

    private func teamCard(_ title: String, _ detail: String, _ ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FaceStack(ids: ids, size: 50)
            Text(title).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
            Text(detail).font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
            PillButton(title: "Preview \(title)", symbol: "eye", look: .filled, wide: true) { previewing = true }
        }
        .padding(16)
        .kCard(radius: 22)
    }

    private var importTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            EmptyNote(text: "Choose a JSON or Markdown package. Up to 4 MB.", symbol: "shippingbox").kCard(radius: 22)
            GoldButton(title: "Choose a package file") { picking = true }
            HintLine(text: "Imported skills and connections stay off until you review them.", symbol: "lock")
        }
    }

    private var shareTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share bot personas").font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
            HintLine(text: "Preview what travels. Keys, models, access and chats stay here.", symbol: "lock")
            BotsSection {
                ForEach(Array(store.bots.filter { !$0.isKip }.enumerated()), id: \.element.id) { index, bot in
                    if index > 0 { RowLine(inset: 62) }
                    Toggle(isOn: Binding(get: { sharing.contains(bot.id) }, set: { on in if on { sharing.insert(bot.id) } else { sharing.remove(bot.id) } })) {
                        HStack(spacing: 12) {
                            BotFace(bot: bot, size: 34)
                            Text("Share \(bot.name)").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        }
                    }
                    .tint(Palette.gold).padding(.horizontal, 14).frame(minHeight: 54)
                }
            }
            BotsSection {
                ToggleRow(title: "Include paused routines", isOn: $pausedRoutines)
                RowLine()
                ToggleRow(title: "Include their teams", isOn: $theirTeams)
                RowLine()
                ToggleRow(title: "Include their rooms", isOn: $theirRooms)
            }
            if exported {
                HintLine(text: "\(sharing.count) bots, \(pausedRoutines ? store.routines.filter { sharing.contains($0.botID) }.count : 0) routines. Nothing secret is included.", symbol: "checkmark.circle", color: Palette.success)
                ShareLink(item: exportText, preview: SharePreview("bots.kairos.json")) {
                    Text("Share package").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.onGold)
                        .frame(maxWidth: .infinity, minHeight: 54).background(Palette.gold, in: Capsule())
                }
            } else {
                GoldButton(title: "Preview export") {
                    guard !sharing.isEmpty else { store.say("Choose at least one bot."); return }
                    withAnimation(Motion.snappy) { exported = true }
                }
            }
        }
    }

    private var exportText: String {
        let names = store.bots.filter { sharing.contains($0.id) }.map { "{\"name\": \"\($0.name)\", \"job\": \"\($0.role)\"}" }
        return "{\"bots\": [\(names.joined(separator: ", "))], \"teams\": \(theirTeams), \"rooms\": \(theirRooms)}"
    }
}

struct PackagePreviewSheet: View {
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var parts = BotsSample.packageParts
    @State private var teams = true
    @State private var rooms = true
    @State private var models: [String: String] = [:]

    var body: some View {
        let bots = parts.filter { $0.kind == "Bot" && $0.include }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: "Package preview", detail: "\(bots.count) bots, 2 paused routines, \(parts.filter { $0.kind == "Skill" && $0.include }.count) skills, \(parts.filter { $0.kind == "Connection" && $0.include }.count) connections")
                BotsSection(title: "What to add") {
                    ForEach($parts) { $part in
                        Toggle(isOn: $part.include) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Include \(part.name)").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                Text(part.kind).font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                            }
                        }
                        .tint(Palette.gold).padding(.horizontal, 14).frame(minHeight: 54)
                    }
                    RowLine()
                    ToggleRow(title: "Their teams", isOn: $teams)
                    RowLine()
                    ToggleRow(title: "Their rooms", isOn: $rooms)
                }
                BotsSection(title: "Models", footer: "About 40% of running every bot on a strong model. An estimate, not a quote.") {
                    ForEach(Array(bots.enumerated()), id: \.element.id) { index, part in
                        if index > 0 { RowLine() }
                        MenuRow(title: "Model for \(part.name)", options: BotsSample.models.map(\.name), selection: Binding(
                            get: { models[part.name] ?? (index == 0 ? "Claude Opus" : "Claude Haiku") },
                            set: { models[part.name] = $0 }
                        ))
                    }
                }
                HintLine(text: "Connections arrive switched off. Add their keys on your desktop.", symbol: "exclamationmark.triangle", color: Palette.goldText)
                GoldButton(title: "Add \(bots.count) bots") {
                    for part in bots {
                        var draft = NewBotDraft()
                        draft.name = store.bots.contains { $0.name == part.name } ? "\(part.name) 2" : part.name
                        draft.job = "From a package"
                        draft.colorHex = BotLook.colors.randomElement()?.hex ?? Palette.botSage
                        draft.model = models[part.name] ?? "Claude Haiku"
                        store.create(draft)
                    }
                    store.say("Added \(bots.count) bots.")
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .kSheet()
    }
}
