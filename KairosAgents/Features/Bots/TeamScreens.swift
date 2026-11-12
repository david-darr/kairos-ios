import SwiftUI

// Teams: the team page, its sheets, the team report, the team map and departments.

enum TeamSheet: String, Identifiable {
    case manage, instructions, memory, settings, models, chief, rename, delete, newTeam, newRoom
    var id: String { rawValue }
}

extension BotsStore {
    func teamIndex(_ id: String) -> Int? { teams.firstIndex { $0.id == id } }

    func setPaused(_ teamID: String, _ paused: Bool) {
        guard let index = teamIndex(teamID) else { return }
        withAnimation(Motion.snappy) { teams[index].paused = paused }
        say(paused ? "\(teams[index].name) is paused" : "\(teams[index].name) is back at work")
    }
}

/// Stacked faces of a few bots.
struct FaceStack: View {
    let ids: [String]
    var size: CGFloat = 34
    let store = BotsStore.shared

    var body: some View {
        HStack(spacing: -size * 0.35) {
            ForEach(Array(ids.prefix(4).enumerated()), id: \.offset) { index, id in
                BotFace(bot: store.bot(id), size: size, stage: Palette.surfaceSolid)
                    .background(Circle().fill(Palette.surfaceSolid).padding(size * 0.08))
                    .zIndex(Double(10 - index))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Team page

struct TeamScreen: View {
    let teamID: String
    var openSheet: TeamSheet? = nil
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: TeamSheet?
    @State private var opened = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        if let team = store.teams.first(where: { $0.id == teamID }) {
            content(team)
        } else {
            BotsPage("Team") { EmptyNote(text: "This team was deleted.", symbol: "person.3") }
        }
    }

    private func content(_ team: BotTeam) -> some View {
        let rooms = store.rooms.filter { room in room.members.contains { team.members.contains($0) } }
        let routines = store.routines.filter { team.members.contains($0.botID) }
        let handoffs = store.handoffs.filter { team.members.contains($0.from) || team.members.contains($0.to) }
        return BotsPage(team.name, subtitle: team.department, trailing: { optionsMenu(team) }) {
            VStack(spacing: 10) {
                FaceStack(ids: team.members, size: 64)
                Text(team.name).font(KFont.display(36)).foregroundStyle(Palette.ink)
                Text("\(team.members.count) bots · \(team.department)\(team.chief.map { " · led by \(store.bot($0).name)" } ?? "")")
                    .font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
            }
            .frame(maxWidth: .infinity)

            if team.paused {
                HintLine(text: "The team is paused. Its bots only read until you resume it.", symbol: "pause.circle.fill", color: Palette.goldText)
                    .padding(12)
                    .background(Palette.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            PillButton(title: team.paused ? "Resume team" : "Pause team", symbol: team.paused ? "play.fill" : "pause.fill", look: team.paused ? .filled : .plain, wide: true) {
                Haptics.thud()
                store.setPaused(team.id, !team.paused)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Members").padding(.horizontal, 4)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(team.members.enumerated()), id: \.element) { index, id in
                        memberFace(id, chief: team.chief == id).arrives(index)
                    }
                }
            }

            BotsSection(title: "Rooms") {
                if rooms.isEmpty { EmptyNote(text: "No rooms yet.", symbol: "number") }
                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    if index > 0 { RowLine(inset: 54) }
                    NavigationLink(value: BotsRoute.room(room.id)) {
                        NavRow(title: room.name, symbol: "number", detail: room.working.isEmpty ? "\(room.members.count) bots" : "\(room.working.map { store.bot($0).name }.joined(separator: ", ")) working", badge: room.unread)
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }

            BotsSection(title: "Routines") {
                if routines.isEmpty { EmptyNote(text: "No routines in this team.", symbol: "clock") }
                ForEach(Array(routines.prefix(6).enumerated()), id: \.element.id) { index, routine in
                    if index > 0 { RowLine(inset: 62) }
                    NavigationLink(value: BotsRoute.routines(routine.botID)) {
                        HStack(spacing: 12) {
                            BotFace(bot: store.bot(routine.botID), size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(routine.name).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                                Text(routine.on ? routine.sentence : "Paused").font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }

            BotsSection(title: "Hand-offs") {
                if handoffs.isEmpty { EmptyNote(text: "No hand-offs yet.", symbol: "arrow.left.arrow.right") }
                ForEach(Array(handoffs.enumerated()), id: \.element.id) { index, handoff in
                    if index > 0 { RowLine() }
                    HandoffRow(handoff: handoff)
                }
            }

            VStack(spacing: 0) {
                NavigationLink(value: BotsRoute.teamReport(team.id)) { NavRow(title: "Team report", symbol: "chart.bar.doc.horizontal") }
                RowLine(inset: 54)
                NavigationLink(value: BotsRoute.teamMap) { NavRow(title: "Team map", symbol: "map") }
                RowLine(inset: 54)
                NavigationLink(value: BotsRoute.departments) { NavRow(title: "Departments", symbol: "building.2", value: team.department) }
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .kCard(radius: 20)
        }
        .sheet(item: $sheet) { which in
            TeamSheetView(teamID: team.id, which: which) { if which == .delete { dismiss() } }
        }
        .onAppear {
            guard !opened else { return }
            opened = true
            sheet = openSheet
        }
    }

    private func memberFace(_ id: String, chief: Bool) -> some View {
        let bot = store.bot(id)
        return NavigationLink(value: BotsRoute.botPage(id)) {
            VStack(spacing: 6) {
                BotFace(bot: bot, size: 78, showStatus: true, blinks: true)
                    .overlay(alignment: .topLeading) {
                        if chief {
                            Image(systemName: "crown.fill").font(.system(size: 14)).foregroundStyle(Palette.goldText)
                                .padding(5).background(Palette.surfaceSolid, in: Circle())
                                .accessibilityLabel("Chief of Staff")
                        }
                    }
                Text(bot.name).font(KFont.ui(14.5, .medium)).foregroundStyle(Palette.ink)
                Text(bot.statusWord).font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(bot.statusColor)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
        }
        .buttonStyle(PressStyle(scale: 0.93))
        .accessibilityLabel("\(bot.name), \(bot.statusWord)\(chief ? ", Chief of Staff" : "")")
    }

    private func optionsMenu(_ team: BotTeam) -> some View {
        Menu {
            Button { sheet = .manage } label: { Label("Manage bots", systemImage: "person.badge.plus") }
            Button { sheet = .instructions } label: { Label("Team instructions", systemImage: "text.quote") }
            Button { sheet = .memory } label: { Label("Team memory", systemImage: "brain") }
            Button { sheet = .settings } label: { Label("Team settings", systemImage: "slider.horizontal.3") }
            Button { sheet = .models } label: { Label("Suggest models", systemImage: "cpu") }
            Button { sheet = .chief } label: { Label("Chief of Staff", systemImage: "crown") }
            Button { store.setPaused(team.id, !team.paused) } label: { Label(team.paused ? "Resume team" : "Pause team", systemImage: team.paused ? "play" : "pause") }
            Button { sheet = .rename } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { sheet = .delete } label: { Label("Delete team", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .kGlass(Circle(), interactive: true)
        .accessibilityLabel("Team options")
    }
}

/// "Producer → Quill: draft captions", with its status. Opens the room or the bot.
struct HandoffRow: View {
    let handoff: Handoff
    let store = BotsStore.shared

    var body: some View {
        let room = store.rooms.first { $0.messages.contains { $0.handoff?.to == handoff.to && $0.handoff?.from == handoff.from } }
        NavigationLink(value: room.map { BotsRoute.room($0.id) } ?? BotsRoute.botPage(handoff.to)) {
            HStack(spacing: 10) {
                FaceStack(ids: [handoff.from, handoff.to], size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.bot(handoff.from).name) → \(store.bot(handoff.to).name): \(handoff.reason)")
                        .font(KFont.ui(14.5)).foregroundStyle(Palette.ink).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(handoff.verb).font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                        StateTag(text: handoff.status, color: statusColor, pulsing: handoff.status == "Working")
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }

    private var statusColor: Color {
        switch handoff.status {
        case "Done": Palette.success
        case "Failed": Palette.danger
        case "Working": Palette.working
        case "Waiting for you": Palette.goldText
        default: Palette.inkDim
        }
    }
}

// MARK: - Team sheets

struct TeamSheetView: View {
    let teamID: String
    let which: TeamSheet
    var after: () -> Void = {}
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var members: Set<String> = []
    @State private var text = ""
    @State private var loaded = false
    // memory
    @State private var kind = "Decisions"
    @State private var entryName = ""
    @State private var entryDetail = ""
    // settings
    @State private var approval = "Keep approval"
    @State private var model = "Keep model"
    @State private var effort = "Keep effort"
    @State private var previewed = false
    // models
    @State private var picks: [String: String] = [:]

    var body: some View {
        let team = store.teams.first { $0.id == teamID }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let team { content(team) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .kSheet()
        .botsToast()
        .onAppear {
            guard !loaded, let team else { return }
            loaded = true
            members = Set(team.members)
            text = which == .rename ? team.name : team.instructions
        }
    }

    @ViewBuilder
    private func content(_ team: BotTeam) -> some View {
        switch which {
        case .manage: manage(team)
        case .instructions: instructions(team)
        case .memory: memory(team)
        case .settings: settings(team)
        case .models: models(team)
        case .chief: chief(team)
        case .rename: rename(team)
        case .delete: delete(team)
        case .newTeam, .newRoom: EmptyView()
        }
    }

    private func botChecks(limit: Int = 20) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(store.bots.enumerated()), id: \.element.id) { index, bot in
                if index > 0 { RowLine(inset: 62) }
                Button {
                    Haptics.select()
                    if members.contains(bot.id) { members.remove(bot.id) } else if members.count < limit { members.insert(bot.id) }
                } label: {
                    HStack(spacing: 12) {
                        BotFace(bot: bot, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bot.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                            Text(store.team(of: bot.id).map { "In \($0.name)" } ?? bot.role).font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        Image(systemName: members.contains(bot.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 21)).foregroundStyle(members.contains(bot.id) ? Palette.goldText : Palette.inkFaint)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.98))
                .accessibilityAddTraits(members.contains(bot.id) ? .isSelected : [])
            }
        }
        .kCard(radius: 20)
    }

    private func manage(_ team: BotTeam) -> some View {
        Group {
            SheetTitle(title: "Manage bots", detail: "A bot can be in one team. Moving it here takes it out of its old team.")
            botChecks()
            GoldButton(title: "Save team") {
                guard let index = store.teamIndex(team.id) else { return }
                for id in members where !team.members.contains(id) { store.moveBot(id, toTeam: team.id) }
                store.teams[index].members = store.teams[index].members.filter { members.contains($0) }
                Haptics.success()
                store.say("Team saved")
                dismiss()
            }
        }
    }

    private func instructions(_ team: BotTeam) -> some View {
        Group {
            SheetTitle(title: "Team instructions", detail: "Every bot in \(team.name) reads these.")
            FieldCard(title: "Instructions", text: $text, placeholder: "How this team works", lines: 6...14)
            Text("\(text.utf8.count) / 24,000 bytes").font(KFont.ui(12.5)).foregroundStyle(text.utf8.count > 24_000 ? Palette.danger : Palette.inkFaint)
            GoldButton(title: "Save instructions") {
                guard let index = store.teamIndex(team.id) else { return }
                store.teams[index].instructions = text
                store.say("Instructions saved")
                dismiss()
            }
        }
    }

    private func memory(_ team: BotTeam) -> some View {
        let kinds = ["People", "Places", "Decisions", "Terms"]
        return Group {
            SheetTitle(title: "Team memory", detail: "What the whole team remembers.")
            ForEach(kinds, id: \.self) { group in
                let entries = team.memory.filter { $0.section == group }
                if !entries.isEmpty {
                    BotsSection(title: group) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, note in
                            if index > 0 { RowLine() }
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.text).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                                    Text("Added by \(note.addedBy), \(note.when)").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer()
                                Button {
                                    guard let i = store.teamIndex(team.id) else { return }
                                    withAnimation(Motion.snappy) { store.teams[i].memory.removeAll { $0.id == note.id } }
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(Palette.danger).frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Delete")
                            }
                            .padding(.leading, 14)
                        }
                    }
                }
            }
            if team.memory.isEmpty { EmptyNote(text: "No team memories yet.", symbol: "brain").kCard(radius: 20) }
            SectionLabel(text: "Add entry")
            GoldSegmented(items: kinds, selection: $kind) { $0 }
            FieldCard(title: "Name", text: $entryName, placeholder: "Short name", limit: 120)
            FieldCard(title: "Detail", text: $entryDetail, placeholder: "What to remember", limit: 600, lines: 2...5)
            GoldButton(title: "Add memory") {
                guard let index = store.teamIndex(team.id), !entryName.isEmpty else { Haptics.thud(); return }
                let line = entryDetail.isEmpty ? entryName : "\(entryName): \(entryDetail)"
                withAnimation(Motion.snappy) { store.teams[index].memory.append(MemoryNote(section: kind, text: line, addedBy: "you", when: "just now")) }
                entryName = ""
                entryDetail = ""
                store.say("Remembered")
            }
        }
    }

    private func settings(_ team: BotTeam) -> some View {
        let approvals = ["Keep approval"] + ApprovalLevel.allCases.map(\.title)
        let modelNames = ["Keep model"] + BotsSample.models.map(\.name)
        let efforts = ["Keep effort"] + Effort.allCases.map(\.title)
        return Group {
            SheetTitle(title: "Team settings", detail: "Change every bot in \(team.name) at once.")
            BotsSection {
                MenuRow(title: "Approval", options: approvals, selection: $approval)
                RowLine()
                MenuRow(title: "Model", options: modelNames, selection: $model)
                RowLine()
                MenuRow(title: "Effort", options: efforts, selection: $effort)
            }
            .onChange(of: approval) { previewed = false }
            .onChange(of: model) { previewed = false }
            .onChange(of: effort) { previewed = false }
            PillButton(title: "Preview changes", symbol: "eye", wide: true) {
                withAnimation(Motion.snappy) { previewed = true }
            }
            if previewed {
                BotsSection(title: "Preview") {
                    ForEach(Array(team.members.enumerated()), id: \.element) { index, id in
                        if index > 0 { RowLine(inset: 62) }
                        HStack(spacing: 12) {
                            BotFace(bot: store.bot(id), size: 34)
                            Text(store.bot(id).name).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                            Spacer()
                            StateTag(text: willChange(id) ? "Will change" : "Unchanged", color: willChange(id) ? Palette.goldText : Palette.inkFaint)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 52)
                    }
                }
            }
            GoldButton(title: "Apply changes") {
                var count = 0
                for id in team.members where willChange(id) {
                    var s = store.settings(id)
                    if let level = ApprovalLevel.allCases.first(where: { $0.title == approval }) { s.approval = level }
                    if model != "Keep model" { s.model = model }
                    if let e = Effort.allCases.first(where: { $0.title == effort }) { s.effort = e }
                    store.save(id, s)
                    count += 1
                }
                Haptics.success()
                store.say("\(count) bots updated")
                dismiss()
            }
            .disabled(!previewed)
            .opacity(previewed ? 1 : 0.5)
        }
    }

    private func willChange(_ id: String) -> Bool {
        let s = store.settings(id)
        return (approval != "Keep approval" && s.approval.title != approval)
            || (model != "Keep model" && s.model != model)
            || (effort != "Keep effort" && s.effort.title != effort)
    }

    private func models(_ team: BotTeam) -> some View {
        Group {
            SheetTitle(title: "Suggest models", detail: "A lighter model where the work is simple saves your plan.")
            ForEach(team.members, id: \.self) { id in
                let current = store.settings(id).model
                let tier = id == team.chief ? "Strong" : (store.bot(id).role.contains("Research") ? "Standard" : "Light")
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        BotFace(bot: store.bot(id), size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.bot(id).name).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                            Text("\(tier) work · now \(current)").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                        }
                    }
                    MenuRow(title: "Model for \(store.bot(id).name)", options: ["Keep its model"] + BotsSample.models.map(\.name), selection: Binding(
                        get: { picks[id] ?? suggestion(tier) },
                        set: { picks[id] = $0 }
                    ))
                    .kCard(radius: 16)
                }
                .padding(12)
                .kCard(radius: 20)
            }
            HintLine(text: "Estimated cost: about 40% of running every bot on a strong model. An estimate, not a quote.", symbol: "dollarsign.circle")
            GoldButton(title: "Apply these models") {
                var count = 0
                for id in team.members {
                    let pick = picks[id] ?? suggestion(id == team.chief ? "Strong" : "Light")
                    guard pick != "Keep its model", pick != store.settings(id).model else { continue }
                    var s = store.settings(id)
                    s.model = pick
                    store.save(id, s)
                    count += 1
                }
                store.say("Updated \(count) bots.")
                dismiss()
            }
        }
    }

    private func suggestion(_ tier: String) -> String {
        switch tier {
        case "Strong": "Claude Opus"
        case "Standard": "Claude Sonnet"
        default: "Claude Haiku"
        }
    }

    private func chief(_ team: BotTeam) -> some View {
        Group {
            SheetTitle(title: "Chief of Staff", detail: "One Chief of Staff can coordinate this team.")
            VStack(spacing: 0) {
                ForEach(Array(team.members.enumerated()), id: \.element) { index, id in
                    if index > 0 { RowLine(inset: 62) }
                    Button {
                        guard let i = store.teamIndex(team.id) else { return }
                        Haptics.success()
                        store.teams[i].chief = id
                        if let old = team.chief { store.chiefs.remove(old) }
                        store.chiefs.insert(id)
                        store.say("\(store.bot(id).name) is Chief of Staff for \(team.name)")
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            BotFace(bot: store.bot(id), size: 36)
                            Text(store.bot(id).name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                            Spacer()
                            if team.chief == id { Image(systemName: "crown.fill").foregroundStyle(Palette.goldText) }
                        }
                        .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                }
            }
            .kCard(radius: 20)
            if team.chief != nil {
                PillButton(title: "Remove chief", look: .danger, wide: true) {
                    guard let i = store.teamIndex(team.id) else { return }
                    if let old = team.chief { store.chiefs.remove(old) }
                    store.teams[i].chief = nil
                    dismiss()
                }
            }
        }
    }

    private func rename(_ team: BotTeam) -> some View {
        Group {
            SheetTitle(title: "Rename team")
            FieldCard(title: "Team name", text: $text, placeholder: "Team name", limit: 60)
            GoldButton(title: "Save") {
                let name = text.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name.count <= 60, let i = store.teamIndex(team.id) else { store.say("Use a short team name."); return }
                store.teams[i].name = name
                dismiss()
            }
        }
    }

    private func delete(_ team: BotTeam) -> some View {
        Group {
            SheetTitle(title: "Delete \(team.name)?", detail: "Remove this team. Its bots keep their conversations.")
            PillButton(title: "Delete team", look: .danger, wide: true) {
                Haptics.thud()
                store.teams.removeAll { $0.id == team.id }
                store.say("\(team.name) was deleted")
                dismiss()
                after()
            }
            QuietButton(title: "Cancel") { dismiss() }
        }
    }
}

// MARK: - New team and new room

struct NewTeamSheet: View {
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var department = "Operations"
    @State private var members: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: "New team")
                FieldCard(title: "Team name", text: $name, placeholder: "e.g. Shop floor", limit: 60)
                BotsSection {
                    MenuRow(title: "Department", options: departments, selection: $department)
                }
                SectionLabel(text: "Bots")
                VStack(spacing: 0) {
                    ForEach(Array(store.bots.filter { !$0.isKip }.enumerated()), id: \.element.id) { index, bot in
                        if index > 0 { RowLine(inset: 62) }
                        Button {
                            Haptics.select()
                            if members.contains(bot.id) { members.remove(bot.id) } else { members.insert(bot.id) }
                        } label: {
                            HStack(spacing: 12) {
                                BotFace(bot: bot, size: 36)
                                Text(bot.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                if let team = store.team(of: bot.id) {
                                    Text("(\(team.name))").font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer()
                                Image(systemName: members.contains(bot.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 21)).foregroundStyle(members.contains(bot.id) ? Palette.goldText : Palette.inkFaint)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .kCard(radius: 20)
                GoldButton(title: "Save team") {
                    let clean = name.trimmingCharacters(in: .whitespaces)
                    guard !clean.isEmpty else { store.say("Give the team a name."); return }
                    let id = "team-\(UUID().uuidString.prefix(6).lowercased())"
                    for bot in members { store.moveBot(bot, toTeam: nil) }
                    store.teams.append(BotTeam(id: id, name: clean, department: department, members: Array(members), chief: nil, instructions: ""))
                    Haptics.success()
                    store.say("\(clean) is ready")
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .kSheet()
    }

    private var departments: [String] {
        Array(Set(store.teams.map(\.department))).sorted()
    }
}

struct NewRoomSheet: View {
    var created: (String) -> Void = { _ in }
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var context = ""
    @State private var members: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: "New room", detail: "A group chat with your bots. A room needs at least one bot. Up to 20 can join.")
                FieldCard(title: "Name", text: $name, placeholder: "Spring launch", limit: 100)
                FieldCard(title: "Context", text: $context, placeholder: "Optional, like Marketing", limit: 60)
                VStack(spacing: 0) {
                    ForEach(Array(store.bots.enumerated()), id: \.element.id) { index, bot in
                        if index > 0 { RowLine(inset: 62) }
                        Button {
                            Haptics.select()
                            if members.contains(bot.id) { members.remove(bot.id) } else if members.count < 20 { members.insert(bot.id) }
                        } label: {
                            HStack(spacing: 12) {
                                BotFace(bot: bot, size: 36)
                                Text(bot.name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                Spacer()
                                Image(systemName: members.contains(bot.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 21)).foregroundStyle(members.contains(bot.id) ? Palette.goldText : Palette.inkFaint)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .kCard(radius: 20)
                GoldButton(title: members.isEmpty ? "Choose at least one bot" : "Create room with \(members.count) bot\(members.count == 1 ? "" : "s")") {
                    let clean = name.trimmingCharacters(in: .whitespaces)
                    guard !clean.isEmpty, !members.isEmpty else { Haptics.thud(); store.say("Give the room a name and at least one bot."); return }
                    let id = "room-\(UUID().uuidString.prefix(6).lowercased())"
                    store.rooms.append(BotRoom(id: id, name: clean, context: context, members: Array(members), instructions: "", messages: []))
                    Haptics.success()
                    dismiss()
                    created(id)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .kSheet()
    }
}

// MARK: - Team report

struct TeamReportScreen: View {
    let teamID: String
    let store = BotsStore.shared
    @State private var window = "Last 7 days"

    var body: some View {
        let team = store.teams.first { $0.id == teamID }
        let wide = window == "Last 30 days"
        BotsPage("Team report", subtitle: team?.name ?? "") {
            GoldSegmented(items: ["Last 7 days", "Last 30 days"], selection: $window) { $0 }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile("Runs", wide ? "264" : "71")
                tile("Failed", wide ? "9" : "3")
                tile("Tokens", wide ? "5.8M" : "1.4M")
                tile("Spend", wide ? "$14.20" : "$3.90")
            }
            HintLine(text: "The team asked you \(wide ? 22 : 6) times.", symbol: "hand.raised")
            BotsSection(title: "What the team made") {
                ForEach(["Three spring sale captions", "Video: winter bike care", "Rival prices sheet"], id: \.self) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.richtext").foregroundStyle(Palette.goldText).frame(width: 26)
                        Text(item).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 16).frame(minHeight: 50)
                }
            }
            if let team {
                SectionLabel(text: "Members").padding(.horizontal, 4)
                ForEach(Array(team.members.enumerated()), id: \.element) { index, id in
                    memberCard(id, index: index, wide: wide)
                }
            }
        }
    }

    private func memberCard(_ id: String, index: Int, wide: Bool) -> some View {
        let bot = store.bot(id)
        let runs = (wide ? 80 : 22) - index * 4
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                BotFace(bot: bot, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bot.name).font(KFont.ui(16.5, .semibold)).foregroundStyle(Palette.ink)
                    Text("\(store.settings(id).model) · last run \(index == 0 ? "now" : "\(index * 2) h ago")").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
                }
                Spacer()
            }
            HStack {
                stat("Runs", "\(runs)")
                stat("Failed", "\(index)")
                stat("Spend", String(format: "$%.2f", Double(runs) * 0.05))
                stat("Approvals", "\(index + 1)")
            }
            NavigationLink(value: BotsRoute.report(id)) {
                Text("Open report").font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44).background(Palette.ink.opacity(0.1), in: Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .padding(14)
        .kCard(radius: 20)
        .arrives(index)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink)
            Text(title).font(KFont.ui(11.5)).foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(KFont.label).tracking(1.2).foregroundStyle(Palette.inkFaint)
            Text(value).font(KFont.ui(26, .semibold, relativeTo: .title2)).foregroundStyle(Palette.ink).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(radius: 18)
        .animation(Motion.snappy, value: window)
    }
}

// MARK: - Team map

struct TeamMapScreen: View {
    let store = BotsStore.shared
    @State private var tags: Set<String> = []
    @State private var message = ""
    @State private var receipts: [String] = []
    @State private var showHandoffs = false
    @State private var newTeam = false
    @State private var newRoom = false
    @State private var moving: (bot: String, team: String?)?
    @State private var goto: BotsRoute?

    var body: some View {
        let unteamed = store.bots.filter { store.team(of: $0.id) == nil }
        BotsPage("Team map", trailing: {
            HStack(spacing: 8) {
                GlassIconButton(symbol: "number", label: "New room") { newRoom = true }
                GlassIconButton(symbol: "plus", label: "New team") { newTeam = true }
            }
        }) {
            composer
            ForEach(Array(store.teams.enumerated()), id: \.element.id) { index, team in
                teamCard(team).arrives(index)
            }
            if !unteamed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Other bots").padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(unteamed.enumerated()), id: \.element.id) { index, bot in
                            if index > 0 { RowLine(inset: 62) }
                            botTile(bot, chief: false)
                        }
                    }
                    .kCard(radius: 20)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(Motion.snappy) { showHandoffs.toggle() }
                } label: {
                    HStack {
                        Text("Handoffs \(store.handoffs.count)").font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: showHandoffs ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.99))
                if showHandoffs {
                    ForEach(store.handoffs) { handoff in
                        RowLine()
                        HandoffRow(handoff: handoff)
                    }
                }
            }
            .kCard(radius: 20)
        }
        .navigationDestination(item: $goto) { BotsDestination(route: $0) }
        .sheet(isPresented: $newTeam) { NewTeamSheet() }
        .sheet(isPresented: $newRoom) { NewRoomSheet { id in goto = .room(id) } }
        .sheet(isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } })) {
            if let moving {
                let teamName = moving.team.flatMap { id in store.teams.first { $0.id == id }?.name } ?? "Other bots"
                ConfirmSheet(title: "Move this bot to \(teamName)?", detail: "\(store.bot(moving.bot).name) keeps its conversations and routines.", confirm: "Move bot", danger: false) {
                    withAnimation(Motion.snappy) { store.moveBot(moving.bot, toTeam: moving.team) }
                    store.say("\(store.bot(moving.bot).name) moved to \(teamName)")
                }
            }
        }
    }

    private var composer: some View {
        let options = ["@everyone"] + store.teams.map { "@\($0.name)" } + store.bots.map { "@\($0.name)" }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Send to bots or teams").font(KFont.ui(16, .semibold)).foregroundStyle(Palette.ink)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { tag in
                        let on = tags.contains(tag)
                        Button {
                            Haptics.select()
                            if on { tags.remove(tag) } else { tags.insert(tag) }
                        } label: {
                            Text(tag).font(KFont.ui(14.5, on ? .semibold : .regular))
                                .foregroundStyle(on ? Palette.onGold : Palette.ink)
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Tag @bots, a team or @everyone", text: $message, axis: .vertical)
                    .font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1...4)
                    .padding(12)
                    .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.onGold)
                        .frame(width: 44, height: 44).background(Palette.gold, in: Circle())
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .disabled(tags.isEmpty || message.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(tags.isEmpty || message.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                .accessibilityLabel("Send")
            }
            if !receipts.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(receipts, id: \.self) { receipt in
                        Label(receipt, systemImage: "checkmark").font(KFont.ui(12.5, .medium)).foregroundStyle(Palette.success)
                            .padding(.horizontal, 10).frame(minHeight: 28)
                            .background(Palette.success.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .padding(14)
        .kCard(radius: 20, raised: true)
    }

    private func send() {
        var names: [String] = []
        for tag in tags {
            let name = String(tag.dropFirst())
            if name == "everyone" {
                names = store.bots.map(\.name)
                break
            } else if let team = store.teams.first(where: { $0.name == name }) {
                names += team.members.map { store.bot($0).name }
            } else {
                names.append(name)
            }
        }
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        Haptics.success()
        withAnimation(Motion.snappy) {
            receipts = unique.map { "Sent to \($0)" }
            message = ""
        }
    }

    private func teamCard(_ team: BotTeam) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                NavigationLink(value: BotsRoute.team(team.id)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(team.name).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                        Text("\(team.members.count) bots\(team.paused ? " · paused" : "")").font(KFont.ui(12.5)).foregroundStyle(team.paused ? Palette.goldText : Palette.inkFaint)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.98))
                PillButton(title: team.paused ? "Resume team" : "Pause team", look: team.paused ? .filled : .plain) {
                    store.setPaused(team.id, !team.paused)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            ForEach(team.members, id: \.self) { id in
                RowLine(inset: 62)
                botTile(store.bot(id), chief: team.chief == id)
            }
        }
        .kCard(radius: 20)
        .opacity(team.paused ? 0.85 : 1)
    }

    private func botTile(_ bot: Bot, chief: Bool) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: BotsRoute.botPage(bot.id)) {
                HStack(spacing: 12) {
                    BotFace(bot: bot, size: 38, showStatus: true)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(bot.name).font(KFont.ui(15.5, .medium)).foregroundStyle(Palette.ink)
                            if chief { Image(systemName: "crown.fill").font(.system(size: 11)).foregroundStyle(Palette.goldText).accessibilityLabel("Chief of Staff") }
                        }
                        Text(bot.status == .offline ? "No signal" : bot.statusWord).font(KFont.ui(12.5)).foregroundStyle(bot.statusColor)
                    }
                    Spacer(minLength: 4)
                    Text(store.settings(bot.id).model).font(KFont.ui(12)).foregroundStyle(Palette.inkDim)
                        .padding(.horizontal, 8).frame(minHeight: 24).background(Palette.ink.opacity(0.07), in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            Menu {
                Button { goto = .botPage(bot.id) } label: { Label("Chat and settings", systemImage: "bubble.left") }
                Button { goto = .report(bot.id) } label: { Label("Report for \(bot.name)", systemImage: "chart.bar.doc.horizontal") }
                Menu("Move to team") {
                    ForEach(store.teams.filter { !$0.members.contains(bot.id) }) { team in
                        Button(team.name) { moving = (bot.id, team.id) }
                    }
                    if store.team(of: bot.id) != nil {
                        Button("Other bots") { moving = (bot.id, nil) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkDim)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(bot.name)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 56)
    }
}

// MARK: - Departments

struct DepartmentsScreen: View {
    let store = BotsStore.shared
    @State private var naming = false
    @State private var newName = ""
    @State private var moveTeam: String?

    var body: some View {
        let departments = Array(Set(store.teams.map(\.department))).sorted()
        BotsPage("Departments", subtitle: "\(departments.count) departments, \(store.teams.count) teams", trailing: {
            GlassIconButton(symbol: "plus", label: "New department") { newName = ""; naming = true }
        }) {
            HintLine(text: "Departments group your teams. A team belongs to one department.")
            ForEach(Array(departments.enumerated()), id: \.element) { index, department in
                let teams = store.teams.filter { $0.department == department }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: department).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(teams.enumerated()), id: \.element.id) { row, team in
                            if row > 0 { RowLine(inset: 86) }
                            teamRow(team, departments: departments)
                        }
                    }
                    .kCard(radius: 20)
                }
                .arrives(index)
            }
        }
        .alert("New department", isPresented: $naming) {
            TextField("Department name", text: $newName)
            Button("Next") {
                if !newName.trimmingCharacters(in: .whitespaces).isEmpty { moveTeam = "" }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Then choose a team to put in it.")
        }
        .confirmationDialog("Move a team to \(newName)", isPresented: Binding(get: { moveTeam != nil }, set: { if !$0 { moveTeam = nil } }), titleVisibility: .visible) {
            ForEach(store.teams) { team in
                Button(team.name) {
                    if let i = store.teamIndex(team.id) {
                        withAnimation(Motion.snappy) { store.teams[i].department = newName }
                        store.say("\(team.name) is in \(newName)")
                    }
                    moveTeam = nil
                }
            }
        }
    }

    private func teamRow(_ team: BotTeam, departments: [String]) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: BotsRoute.team(team.id)) {
                HStack(spacing: 12) {
                    FaceStack(ids: team.members, size: 34).frame(width: 60, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(team.name).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                        Text("\(team.members.count) bots\(team.paused ? " · paused" : "")").font(KFont.ui(12.5)).foregroundStyle(team.paused ? Palette.goldText : Palette.inkFaint)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            Menu {
                ForEach(departments.filter { $0 != team.department }, id: \.self) { department in
                    Button("Move to \(department)") {
                        if let i = store.teamIndex(team.id) { withAnimation(Motion.snappy) { store.teams[i].department = department } }
                    }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkDim)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Move \(team.name)")
        }
        .padding(.leading, 14).padding(.trailing, 4).frame(minHeight: 60)
    }
}
