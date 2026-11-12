import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Studio's libraries: Formats, Styles, Characters (with sheet approval), Connections and Templates.

struct StudioLibraryView: View {
    let library: StudioLibrary

    var body: some View {
        switch library {
        case .formats: FormatsLibrary()
        case .styles: StylesLibrary()
        case .characters: CharactersLibrary()
        case .connections: ConnectionsLibrary()
        case .templates: TemplatesLibrary()
        }
    }
}

// MARK: - Formats

struct FormatsLibrary: View {
    @Environment(MakeStore.self) private var make

    var body: some View {
        let studio = make.studio
        VStack(alignment: .leading, spacing: 12) {
            Text("A format card is a shape of video that works, with its sources. A port carries it into one of your niches.")
                .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            if studio.formats.isEmpty {
                EmptyLine(text: "No format cards yet. The Researcher writes one when it finds a format that works, with its sources.")
            }
            ForEach(studio.formats) { format in FormatCardView(format: format) }
            MakeTile(title: "Style packs", symbol: "paintbrush") {
                ForEach(studio.packs) { pack in
                    HStack {
                        Text(pack.name).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                        Spacer()
                        StatePill(text: pack.versions.contains { $0.status == .approved } ? "Built" : "Not built yet", tone: pack.versions.contains { $0.status == .approved } ? .ok : .muted)
                    }
                    .frame(minHeight: 36)
                }
            }
        }
    }
}

struct FormatCardView: View {
    let format: StudioFormat
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(format.name).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
            HStack(spacing: 6) {
                StatePill(text: format.length, tone: .muted)
                StatePill(text: "Seen in \(format.seenIn)", tone: .muted)
            }
            .scrollableRow()
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(format.beats.enumerated()), id: \.offset) { index, beat in
                    Text("\(index + 1). \(beat)").font(KFont.ui(14.5)).foregroundStyle(Palette.ink)
                }
            }
            Text(format.audience).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
            ForEach(format.evidence, id: \.self) { line in
                Label(line, systemImage: "link").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            }
            Text("Not ours to use: the sources stay theirs. Only the shape is ported.").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
            DisclosureGroup(isExpanded: $open) {
                VStack(alignment: .leading, spacing: 10) {
                    if format.ports.isEmpty { EmptyLine(text: "Not ported into any of your niches yet.") }
                    ForEach(format.ports) { port in portRow(port) }
                }
                .padding(.top, 8)
            } label: {
                Text("Ports (\(format.ports.count))").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
            }
            .tint(Palette.goldText)
        }
        .padding(14)
        .kCard(radius: 22)
    }

    private func portRow(_ port: StudioPort) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("From \(port.from) into \(port.to)").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                Spacer(minLength: 6)
                StatePill(text: port.status, tone: port.status == "Accepted" ? .ok : .working)
            }
            Text(port.reason).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            ForEach(port.changes, id: \.self) { Text("· \($0)").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim) }
            if port.checks.isEmpty {
                Text("Not checked yet.").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            } else {
                HStack(spacing: 6) {
                    ForEach(port.checks) { check in
                        StatePill(text: "\(check.name): \(check.result)", tone: check.result == "Passed" ? .ok : (check.result == "Warning" ? .warn : .error))
                    }
                }
                .scrollableRow()
            }
            Text(port.cost).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            Text("Evaluator: \(port.verdict)").font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.ink)
        }
        .padding(12)
        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Styles

struct StylesLibrary: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PillButton(title: "New from a brief", symbol: "plus", filled: true) { studio.sheet = .newBrief }
                PillButton(title: "Import") { studio.sheet = .importPack }
            }
            .scrollableRow()
            if !studio.packs.contains(where: { $0.name == "Blocky voxel 3D starter" }) {
                PillButton(title: "Add Blocky voxel 3D starter") {
                    withAnimation(Motion.snappy) {
                        studio.packs.append(StudioPack(id: UUID().uuidString, name: "Blocky voxel 3D starter", origin: "Starter pack", summary: "Toy blocks, bright worlds.", brief: "The starter voxel look.", versions: [PackVersion(number: 1, status: .draft, note: "Starter.")]))
                    }
                    toast.say("Starter pack added as a draft.")
                }
            }
            if studio.packs.isEmpty {
                EmptyLine(text: "No style packs yet. Write a brief, add the starter pack, or import a pack file.")
            }
            ForEach(studio.packs) { pack in PackGroup(pack: pack) }
            MakeTile(title: "Built into Kairos", symbol: "shippingbox") {
                ForEach(["Motion type", "Flat 2D explainer", "Glossy 3D mascot", "Blocky voxel 3D", "Story Short"], id: \.self) { engine in
                    HStack {
                        Text(engine).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                        Spacer()
                        StatePill(text: engine == "Story Short" ? "Not built yet" : "Available", tone: engine == "Story Short" ? .muted : .ok)
                    }
                    .frame(minHeight: 34)
                }
            }
        }
    }
}

struct PackGroup: View {
    let pack: StudioPack
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @State private var showBrief = false

    var body: some View {
        let studio = make.studio
        let approved = pack.versions.contains { $0.status == .approved }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
                    Text(pack.origin).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                Spacer()
                Menu {
                    Button("Edit", systemImage: "pencil") { studio.sheet = .editPack(pack.id) }
                    Button("Duplicate", systemImage: "plus.square.on.square") { studio.sheet = .duplicatePack(pack.id) }
                    Button("Export", systemImage: "square.and.arrow.up") { toast.say("Exported \(pack.name).json to your desktop's downloads.") }
                    if approved {
                        Button("Share", systemImage: "person.2") { toast.say("Shared to your library.") }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44).background(Palette.ink.opacity(0.1), in: Circle())
                }
                .accessibilityLabel("Pack tools")
            }
            Text(pack.summary).font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
            Text(pack.useText).font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(approved ? Palette.success : Palette.goldText)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(pack.facts.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .firstTextBaseline) {
                        Text(key).font(KFont.ui(13, .medium, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).frame(width: 110, alignment: .leading)
                        Text(pack.facts[key] ?? "").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.ink)
                    }
                }
            }
            DisclosureGroup("Show the brief", isExpanded: $showBrief) {
                Text(pack.brief).font(KFont.ui(14)).foregroundStyle(Palette.inkDim).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }
            .font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink).tint(Palette.goldText)
            ForEach(pack.versions.reversed()) { version in versionRow(version) }
        }
        .padding(14)
        .kCard(radius: 22)
    }

    private func versionRow(_ version: PackVersion) -> some View {
        let studio = make.studio
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Version \(version.number)").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                Spacer()
                StatePill(text: version.status.rawValue, tone: version.status.tone)
            }
            Text(version.note).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            if let reason = version.rejection { Text("Rejected: \(reason)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
            HStack(spacing: 8) {
                switch version.status {
                case .draft, .rejected, .failed:
                    PillButton(title: "Make sample", filled: true) {
                        studio.makeSample(pack.id, version: version.number)
                        toast.say("Rendering the sample. It takes a few minutes.")
                    }
                case .rendering:
                    HStack(spacing: 6) {
                        PulsingDot(color: Palette.working, size: 6)
                        Text("Rendering").font(KFont.ui(14, .medium)).foregroundStyle(Palette.working)
                    }
                    .frame(minHeight: 44)
                case .waiting:
                    PillButton(title: "Review", filled: true) { studio.open(.approvals) }
                    PillButton(title: "Watch the sample") { toast.say("The sample plays on your desktop. Connect it to watch here.") }
                case .approved:
                    PillButton(title: "Watch the sample") { toast.say("The sample plays on your desktop. Connect it to watch here.") }
                    PillButton(title: "Contact sheet") { toast.say("The contact sheet opens on your desktop.") }
                }
            }
            .scrollableRow()
        }
        .padding(12)
        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct BriefSheet: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var brief = ""
    @State private var name = ""
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: "New style pack", detail: "Describe the look and sound. Kairos turns it into a pack.")
                MakeField(label: "Brief", text: $brief, prompt: "Warm paper colours, hand-drawn arrows, calm narration...", limit: 12000, lines: 4...10)
                MakeField(label: "Name (optional)", text: $name, limit: 80)
                if working {
                    HStack(spacing: 8) {
                        PulsingDot(color: Palette.working, size: 7)
                        Text("Turning the brief into a pack...").font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim)
                    }
                }
                GoldButton(title: "Make pack") {
                    guard !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { toast.say("Write the brief first."); return }
                    working = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        let pack = StudioPack(id: UUID().uuidString, name: name.isEmpty ? "New pack" : name, origin: "Made from a written brief", summary: String(brief.prefix(80)), brief: brief, versions: [PackVersion(number: 1, status: .draft, note: "Made from the brief.")])
                        withAnimation(Motion.snappy) { make.studio.packs.append(pack) }
                        toast.say("Pack made as a draft. Render its sample to send it for your OK.")
                        dismiss()
                    }
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .kSheet()
    }
}

struct EditPackSheet: View {
    let packID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StudioPack?
    @State private var changed = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: "Edit style pack", detail: "Saving makes a new draft version.")
                if draft != nil {
                    MakeField(label: "Name", text: bind(\.name), limit: 80)
                    MakeField(label: "Summary", text: bind(\.summary), limit: 300, lines: 2...4)
                    MakeField(label: "Director brief", text: bind(\.brief), limit: 12000, lines: 3...8)
                    VStack(spacing: 0) {
                        MakeChoiceRow(title: "Music mood", options: ["Energetic", "Calm", "Warm", "Dark", "Playful"], selection: bind(\.music))
                        MakeToggleRow(title: "Captions", isOn: Binding(get: { draft?.captions ?? true }, set: { draft?.captions = $0 }))
                        MakeChoiceRow(title: "Caption case", options: ["Sentence", "Upper"], selection: bind(\.captionCase))
                        MakeChoiceRow(title: "Narrator voice", options: ["Iris", "Ryan", "Wren", "Theo"], selection: bind(\.narrator), last: true)
                    }
                    .kCard(radius: 18)
                    MakeField(label: "What changed", text: $changed, limit: 300, lines: 1...3)
                }
                GoldButton(title: "Save new version") { save() }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .kSheet()
        .onAppear { draft = make.studio.pack(packID) }
    }

    private func bind(_ path: WritableKeyPath<StudioPack, String>) -> Binding<String> {
        Binding(get: { draft?[keyPath: path] ?? "" }, set: { draft?[keyPath: path] = $0 })
    }

    private func save() {
        let studio = make.studio
        guard var draft, let original = studio.pack(packID), let index = studio.packs.firstIndex(where: { $0.id == packID }) else { return }
        guard draft != original else { toast.say("Change something first."); return }
        let number = (original.versions.map(\.number).max() ?? 0) + 1
        draft.versions.append(PackVersion(number: number, status: .draft, note: changed.isEmpty ? "Edited." : changed))
        withAnimation(Motion.snappy) { studio.packs[index] = draft }
        toast.say("Saved as version \(number), a draft.")
        dismiss()
    }
}

struct ImportPackSheet: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var fileName: String?

    var body: some View {
        FittedSheet(estimate: 340) {
            VStack(spacing: 14) {
                SheetTitle(title: "Import a style pack", detail: "Choose a .json pack file.")
                PillButton(title: fileName ?? "Choose a file", symbol: "doc", expand: true) { picking = true }
                GoldButton(title: "Import") {
                    guard let fileName else { toast.say("Choose a pack file first."); return }
                    let name = fileName.replacingOccurrences(of: ".json", with: "")
                    withAnimation(Motion.snappy) {
                        make.studio.packs.append(StudioPack(id: UUID().uuidString, name: name, origin: "Imported", summary: "Imported from a file.", brief: "", versions: [PackVersion(number: 1, status: .draft, note: "Imported.")]))
                    }
                    toast.say("Imported as a draft.")
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { fileName = url.lastPathComponent }
        }
    }
}

// MARK: - Characters

struct CharactersLibrary: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        VStack(alignment: .leading, spacing: 12) {
            PillButton(title: "New character", symbol: "plus", filled: true) { studio.sheet = .newCharacter }
            if studio.characters.isEmpty {
                EmptyLine(text: "No characters yet. Make one here, or the Editor makes one when a channel uses the Flat 2D pack.")
            }
            ForEach(studio.characters) { character in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(character.name).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
                            Text("\(character.family) family · \(character.castable)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        PillButton(title: "New version") { studio.sheet = .characterVersion(character.id) }
                    }
                    ForEach(character.versions.reversed()) { version in
                        HStack(alignment: .top, spacing: 12) {
                            CharacterSheetArt(version: version, family: character.family).frame(width: 96, height: 72)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("Version \(version.number)").font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                                    Spacer(minLength: 4)
                                    StatePill(text: version.status.rawValue, tone: version.status.tone)
                                }
                                Text(version.note).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                                if let reason = version.rejection { Text("Rejected: \(reason)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.danger) }
                                if version.status == .draft || version.status == .rejected {
                                    PillButton(title: "Make sheet", filled: true) {
                                        studio.setCharacter(character.id, version: version.number, status: .waiting)
                                        toast.say("Sheet made. It is waiting for your OK in Approvals.")
                                    }
                                } else if version.status == .waiting {
                                    PillButton(title: "Review", filled: true) { studio.open(.approvals) }
                                }
                            }
                        }
                        .padding(10)
                        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(14)
                .kCard(radius: 22)
            }
        }
    }
}

struct NewCharacterSheet: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var family = "Round"
    @State private var name = ""

    var body: some View {
        FittedSheet(estimate: 420) {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: "New character")
                GlassSwitch(items: ["Round", "Square", "Triangle"], selection: $family) { $0 }
                MakeField(label: "Name (optional)", text: $name, limit: 40)
                GoldButton(title: "Make character") {
                    let character = StudioCharacter(id: UUID().uuidString, name: name.isEmpty ? "New character" : name, family: family, versions: [CharacterVersion(number: 1, status: .draft, note: "New character.", body: 0xCDBFD9, accent: 0x9C7430)])
                    withAnimation(Motion.snappy) { make.studio.characters.append(character) }
                    toast.say("Character made. Make its sheet to send it for approval.")
                    dismiss()
                }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

struct CharacterVersionSheet: View {
    let characterID: String
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast
    @Environment(\.dismiss) private var dismiss
    @State private var body_: UInt32 = 0
    @State private var accent: UInt32 = 0
    @State private var accessory = "None"
    @State private var name = ""
    @State private var changed = ""

    private let swatches: [UInt32] = [0xE8C39E, 0xB9D2E3, 0xD99A92, 0xB5C7A5, 0xCDBFD9, 0xD9B260]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: "New version", detail: make.studio.character(characterID)?.name)
                CharacterSheetArt(version: CharacterVersion(number: 0, status: .draft, note: "", body: body_, accent: accent, accessory: accessory), family: make.studio.character(characterID)?.family ?? "Round")
                    .frame(height: 120)
                swatchRow("Body", selection: $body_)
                swatchRow("Accent", selection: $accent)
                VStack(spacing: 0) {
                    MakeChoiceRow(title: "Accessory", options: ["None", "Scarf", "Antenna", "Leaf", "Cap", "Bow"], selection: $accessory, last: true)
                }
                .kCard(radius: 18)
                MakeField(label: "Name", text: $name, limit: 40)
                MakeField(label: "What changed", text: $changed, limit: 300)
                GoldButton(title: "Save new version") { save() }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .kSheet()
        .onAppear {
            guard let character = make.studio.character(characterID), let last = character.versions.last else { return }
            body_ = last.body
            accent = last.accent
            accessory = last.accessory
            name = character.name
        }
    }

    private func swatchRow(_ title: String, selection: Binding<UInt32>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(KFont.ui(13.5, .medium, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
            HStack(spacing: 10) {
                ForEach(swatches, id: \.self) { hex in
                    Button {
                        Haptics.select()
                        selection.wrappedValue = hex
                    } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(selection.wrappedValue == hex ? Palette.gold : Palette.line, lineWidth: selection.wrappedValue == hex ? 3 : 1))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Colour \(String(hex, radix: 16))")
                    .accessibilityAddTraits(selection.wrappedValue == hex ? .isSelected : [])
                }
            }
        }
    }

    private func save() {
        let studio = make.studio
        guard let index = studio.characters.firstIndex(where: { $0.id == characterID }), let last = studio.characters[index].versions.last else { return }
        let same = last.body == body_ && last.accent == accent && last.accessory == accessory && studio.characters[index].name == name
        guard !same else { toast.say("Change something first."); return }
        let version = CharacterVersion(number: last.number + 1, status: .draft, note: changed.isEmpty ? "New version." : changed, body: body_, accent: accent, accessory: accessory)
        withAnimation(Motion.snappy) {
            studio.characters[index].versions.append(version)
            if !name.isEmpty { studio.characters[index].name = name }
        }
        toast.say("Saved as a draft. Make its sheet to send it for approval.")
        dismiss()
    }
}

// MARK: - Connections

struct ConnectionsLibrary: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        @Bindable var studio = make.studio
        VStack(alignment: .leading, spacing: 12) {
            Text("Kairos reads numbers through your own Google project and your own apps. It posts only what you approve.")
                .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
            PillButton(title: "Add a channel", symbol: "plus") { studio.sheet = .addChannel }
            MakeTile(title: "YouTube", symbol: "play.rectangle") {
                if !studio.youtubeConfigured {
                    Text("Google first: set up your Kairos Google project on your desktop.").font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
                } else {
                    row("Analytics", state: studio.analyticsConnected ? "Connected" : "Not connected") {
                        PillButton(title: "Sync now") { toast.say("Stored numbers for 3 posts.") }
                    }
                    Text("Reads views, watch time, likes and follows once a day. Read-only: it never posts.").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    row("Posting", state: studio.postingConnected ? "Connected" : "Not connected") { EmptyView() }
                    VStack(spacing: 0) {
                        MakeChoiceRow(title: "Uploads ask for", options: ["Private", "Unlisted", "Public"], selection: Binding(get: { studio.uploadPrivacy }, set: { value in
                            studio.uploadPrivacy = value
                            toast.say("Uploads ask for \(value).")
                        }), last: true)
                    }
                    .kCard(radius: 16)
                    ForEach(studio.channels.filter { $0.platform == .youtube }) { channel in
                        HStack(spacing: 10) {
                            ChannelAvatar(channel: channel, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(channel.handle).font(KFont.ui(15, .medium)).foregroundStyle(Palette.ink)
                                Text(channel.connection).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(channel.connection == "Connected" ? Palette.success : Palette.danger)
                            }
                            Spacer(minLength: 0)
                            PillButton(title: channel.connection == "Connected" ? "Change" : "Connect") { studio.sheet = .accountChooser(channel.id) }
                        }
                        if channel.connection == "Needs sign-in" {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Sign in again").font(KFont.ui(14.5, .semibold)).foregroundStyle(Palette.ink)
                                Text("Google signed this channel out. Choose its account again.").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                                PillButton(title: "Check again") { toast.say("Google says: the channel still needs sign-in.") }
                            }
                            .padding(12)
                            .background(Palette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }
            appTile(.tiktok, saved: studio.tiktokAppSaved)
            appTile(.instagram, saved: studio.instagramAppSaved)
            MakeTile(title: "TikTok and Instagram numbers", symbol: "eye") {
                ForEach([StudioPlatform.tiktok, .instagram], id: \.self) { platform in
                    MakeToggleRow(title: "Read \(platform.name) numbers", detail: studio.pageReads[platform] == true ? "On. 4 of 12 page reads today." : "Off.", isOn: Binding(get: { studio.pageReads[platform] ?? false }, set: { value in
                        studio.pageReads[platform] = value
                        toast.say("\(platform.name) page reads \(value ? "on" : "off").")
                    }), last: true)
                }
                PillButton(title: "Read now") { toast.say("Reading pages, 20 seconds apart. The desktop app must be open.") }
                Text("Read-only, from your own signed-in pages in the Kairos Browser. At most 12 pages a day per platform.").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
            }
            MakeTile(title: "Niches", symbol: "square.grid.2x2") {
                if studio.niches.isEmpty { EmptyLine(text: "No niches yet.") }
                ForEach(studio.niches) { niche in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(niche.name).font(KFont.ui(15)).foregroundStyle(Palette.ink)
                            Text(niche.retired ? "Retired. History kept." : "\(niche.slots) posting slots a day").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        StatePill(text: niche.retired ? "Retired" : "Live", tone: niche.retired ? .muted : .ok)
                    }
                    .frame(minHeight: 40)
                }
            }
        }
    }

    private func row<Trailing: View>(_ title: String, state: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
            StatePill(text: state, tone: state == "Connected" ? .ok : .warn)
            Spacer()
            trailing()
        }
        .frame(minHeight: 44)
    }

    private func appTile(_ platform: StudioPlatform, saved: Bool) -> some View {
        let studio = make.studio
        return MakeTile(title: "\(platform.name) app", symbol: "app.badge") {
            Text(saved ? "Your app is saved. Channels connect in their settings." : "No app yet. Without one, Prepare post fills the upload page and page reads bring the numbers.")
                .font(KFont.ui(14)).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
            PillButton(title: saved ? "Edit app" : "Set up your app", filled: !saved) { studio.sheet = .socialApp(platform) }
        }
    }
}

// MARK: - Templates

struct TemplatesLibrary: View {
    @Environment(MakeStore.self) private var make
    @Environment(MakeToast.self) private var toast

    var body: some View {
        let studio = make.studio
        VStack(alignment: .leading, spacing: 12) {
            ForEach(studio.templates) { template in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(template.name).font(KFont.ui(18, .semibold)).foregroundStyle(Palette.ink)
                        Spacer()
                        if template.added { StatePill(text: "Added", tone: .ok) }
                    }
                    Text(template.detail).font(KFont.ui(14.5)).foregroundStyle(Palette.inkDim).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ForEach(template.bots, id: \.self) { StatePill(text: $0, tone: .muted) }
                    }
                    .scrollableRow()
                    if !template.added {
                        PillButton(title: "Add this team", filled: true) {
                            if let index = studio.templates.firstIndex(where: { $0.id == template.id }) {
                                withAnimation(Motion.snappy) { studio.templates[index].added = true }
                            }
                            toast.say("\(template.name) added. Every bot starts at Ask and its routines start paused.")
                        }
                    }
                }
                .padding(14)
                .kCard(radius: 22)
            }
        }
    }
}

// MARK: - Drawn previews

struct CharacterSheetArt: View {
    let version: CharacterVersion
    let family: String

    var body: some View {
        ZStack {
            Palette.paper
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { pose in
                    ZStack {
                        shape.fill(Color(hex: version.body)).frame(width: 34, height: 34)
                        HStack(spacing: 6) {
                            Capsule().fill(Palette.night).frame(width: 4, height: 8)
                            Capsule().fill(Palette.night).frame(width: 4, height: 8)
                        }
                        .offset(x: CGFloat(pose - 1) * 3)
                        if version.accessory != "None" {
                            Capsule().fill(Color(hex: version.accent)).frame(width: 26, height: 6).offset(y: version.accessory == "Scarf" ? 16 : -20)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Character sheet")
    }

    private var shape: AnyShape {
        switch family {
        case "Square": AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case "Triangle": AnyShape(TriangleShape())
        default: AnyShape(Circle())
        }
    }
}

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct PackSampleArt: View {
    let name: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xB9D2E3), Color(hex: 0x4E6070)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(hex: 0xE8C39E)).frame(width: 44, height: 44).offset(x: -20, y: 10)
            Image(systemName: "play.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.night)
                .frame(width: 36, height: 36).background(Palette.cream.opacity(0.9), in: Circle())
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Sample video of \(name)")
    }
}

struct ContactSheetArt: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
            ForEach(0..<9, id: \.self) { index in
                Rectangle().fill(Color(hex: [0xB9D2E3, 0xE8C39E, 0xD99A92, 0xB5C7A5, 0xCDBFD9][index % 5]))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(4)
        .background(Palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Contact sheet")
    }
}
