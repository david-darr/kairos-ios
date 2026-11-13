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
    let live = BotsTeamsLive.shared
    let routinesLive = BotsRoutinesLive.shared
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: TeamSheet?
    @State private var opened = false
    @State private var askPause = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    /// Paired: the team, its pause switch, rooms, routines and hand-offs are the desktop's, never samples.
    private var isLive: Bool { !Connection.shared.usesSampleData }

    var body: some View {
        Group {
            if let team = store.teams.first(where: { $0.id == teamID }) {
                content(team)
            } else if isLive && store.rosterLoad != .loaded {
                BotsPage("Team", live: true) {
                    BotsLoadNote(state: store.rosterLoad == .idle ? .loading : store.rosterLoad, waiting: "Reading this team from your desktop.") {
                        Task { await store.loadRoster() }
                    }
                }
            } else if isLive {
                BotsPage("Team", live: true) { EmptyNote(text: "This team is not on your desktop.", symbol: "person.3") }
            } else {
                BotsPage("Team") { EmptyNote(text: "This team was deleted.", symbol: "person.3") }
            }
        }
        .task(id: BotsStore.connectionKey) {
            store.followConnection()
            live.followConnection()
            routinesLive.followConnection()
            guard isLive else { return }
            if store.rosterLoad != .loaded { await store.loadRoster() }
            await live.loadIfNeeded()
            await routinesLive.loadIfNeeded()
        }
    }

    private func content(_ team: BotTeam) -> some View {
        let rooms = store.rooms.filter { room in room.members.contains { team.members.contains($0) } }
        let routines = store.routines.filter { team.members.contains($0.botID) }
        let handoffs = store.handoffs.filter { team.members.contains($0.from) || team.members.contains($0.to) }
        let paused = isLive ? live.paused(team.id) : team.paused
        return BotsPage(team.name, subtitle: isLive ? nil : team.department, live: isLive, trailing: { optionsMenu(team, paused: paused) }) {
            VStack(spacing: 10) {
                FaceStack(ids: team.members, size: 64)
                Text(team.name).font(KFont.display(36)).foregroundStyle(Palette.ink)
                Text("\(team.members.count) bots\(isLive ? "" : " · \(team.department)")\(team.chief.map { " · led by \(store.bot($0).name)" } ?? "")")
                    .font(KFont.ui(14)).foregroundStyle(Palette.inkDim)
            }
            .frame(maxWidth: .infinity)

            if isLive {
                BotsLoadNote(state: live.mapReady ? .loaded : live.shown(live.mapLoad), waiting: "Reading the team from your desktop.") {
                    Task { await live.loadMap(force: false) }
                }
            }
            if paused {
                HintLine(text: "The team is paused. Its bots only read until you resume it.", symbol: "pause.circle.fill", color: Palette.goldText)
                    .padding(12)
                    .background(Palette.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            PillButton(title: paused ? "Resume team" : "Pause team", symbol: paused ? "play.fill" : "pause.fill", look: paused ? .filled : .plain, wide: true) {
                Haptics.thud()
                if isLive {
                    pauseLive(team, paused: paused)
                } else {
                    store.setPaused(team.id, !team.paused)
                }
            }
            .disabled(isLive && live.waits(team.id))
            .opacity(isLive && live.waits(team.id) ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Members").padding(.horizontal, 4)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(team.members.enumerated()), id: \.element) { index, id in
                        memberFace(id, chief: team.chief == id).arrives(index)
                    }
                }
            }

            if isLive {
                liveRooms(team)
                liveRoutines(team)
                liveHandoffs(team)
                links(team)
                HintLine(text: "Add or move bots, and change every member's settings at once, in Kairos on your desktop.", symbol: "desktopcomputer")
                    .padding(.horizontal, 4)
            } else {
                sampleSections(team, rooms: rooms, routines: routines, handoffs: handoffs)
            }
        }
        .sheet(item: $sheet) { which in
            TeamSheetView(teamID: team.id, which: which) { if which == .delete { dismiss() } }
        }
        .sheet(isPresented: $askPause) {
            ConfirmSheet(title: "Pause \(team.name)?", detail: BotTmMap.pauseDetail, confirm: "Pause team") {
                live.setPaused(team.id, name: team.name, true, say: store.say)
            }
        }
        .onAppear {
            guard !opened else { return }
            opened = true
            sheet = openSheet
        }
    }

    /// Paired: pausing asks first; resuming does not.
    private func pauseLive(_ team: BotTeam, paused: Bool) {
        if paused {
            live.setPaused(team.id, name: team.name, false, say: store.say)
        } else {
            askPause = true
        }
    }

    // MARK: Paired sections

    private func liveRooms(_ team: BotTeam) -> some View {
        let rooms = live.shownRooms.filter { room in (room.members ?? []).contains { team.members.contains($0.botId ?? "") } }
        return Group {
            if live.mapReady {
                BotsSection(title: "Rooms") {
                    if rooms.isEmpty { EmptyNote(text: "No rooms yet.", symbol: "number") }
                    ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                        if index > 0 { RowLine(inset: 54) }
                        NavigationLink(value: BotsRoute.room(room.id)) {
                            NavRow(title: room.name ?? "Room", symbol: "number", detail: roomDetail(room), badge: room.unread ?? 0)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
            }
        }
    }

    private func roomDetail(_ room: BotRoomDTO) -> String {
        let members = room.members ?? []
        let working = members.filter { $0.working == true }.compactMap(\.botId).map { store.bot($0).name }
        return working.isEmpty ? "\(members.count) bots" : "\(working.joined(separator: ", ")) working"
    }

    private func liveRoutines(_ team: BotTeam) -> some View {
        let routines = routinesLive.shownRoutines.filter { team.members.contains($0.botID) }
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Routines").padding(.horizontal, 4)
            BotsLoadNote(state: routinesLive.routinesReady ? .loaded : routinesLive.shown(routinesLive.routinesLoad),
                         waiting: "Reading routines from your desktop.") {
                Task { await routinesLive.refreshRoutines(force: false) }
            }
            if routinesLive.routinesReady {
                VStack(spacing: 0) {
                    if routines.isEmpty { EmptyNote(text: "No routines in this team.", symbol: "clock") }
                    ForEach(Array(routines.prefix(6).enumerated()), id: \.element.id) { index, routine in
                        if index > 0 { RowLine(inset: 62) }
                        NavigationLink(value: BotsRoute.routines(routine.botID)) {
                            HStack(spacing: 12) {
                                BotFace(bot: store.bot(routine.botID), size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(routine.name).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                                    Text(routine.on ? routinesLive.sentence(routine) : "Paused").font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .kCard(radius: 20)
                if routines.count > 6 {
                    HintLine(text: "\(routines.count - 6) more. Open a bot's Routines page to see all of its routines.", symbol: "clock")
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func liveHandoffs(_ team: BotTeam) -> some View {
        let edges = live.shownHandoffs.filter { team.members.contains($0.sourceBotId ?? "") || team.members.contains($0.targetBotId ?? "") }
        let rows = edges.compactMap { edge in BotTmMap.handoff(edge).map { (handoff: $0, room: edge.roomId) } }
        return Group {
            if live.mapReady {
                BotsSection(title: "Hand-offs") {
                    if rows.isEmpty { EmptyNote(text: "No hand-offs right now.", symbol: "arrow.left.arrow.right") }
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { RowLine() }
                        HandoffRow(handoff: row.handoff, live: true, roomID: row.room)
                    }
                }
            }
        }
    }

    private func links(_ team: BotTeam) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: BotsRoute.teamReport(team.id)) { NavRow(title: "Team report", symbol: "chart.bar.doc.horizontal") }
            RowLine(inset: 54)
            NavigationLink(value: BotsRoute.teamMap) { NavRow(title: "Team map", symbol: "map") }
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .kCard(radius: 20)
    }

    // MARK: Sample sections

    @ViewBuilder
    private func sampleSections(_ team: BotTeam, rooms: [BotRoom], routines: [Routine], handoffs: [Handoff]) -> some View {
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

    private func optionsMenu(_ team: BotTeam, paused: Bool) -> some View {
        Menu {
            // Paired: moving bots and changing every member at once stay on the desktop.
            if !isLive { Button { sheet = .manage } label: { Label("Manage bots", systemImage: "person.badge.plus") } }
            Button { sheet = .instructions } label: { Label("Team instructions", systemImage: "text.quote") }
            Button { sheet = .memory } label: { Label("Team memory", systemImage: "brain") }
            if !isLive {
                Button { sheet = .settings } label: { Label("Team settings", systemImage: "slider.horizontal.3") }
                Button { sheet = .models } label: { Label("Suggest models", systemImage: "cpu") }
            }
            Button { sheet = .chief } label: { Label("Chief of Staff", systemImage: "crown") }
            Button {
                if isLive { pauseLive(team, paused: paused) } else { store.setPaused(team.id, !team.paused) }
            } label: { Label(paused ? "Resume team" : "Pause team", systemImage: paused ? "play" : "pause") }
                .disabled(isLive && live.waits(team.id))
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
    /// Paired: the room the desktop named for this hand-off (none: it opens the bot it went to).
    var live = false
    var roomID: String? = nil
    let store = BotsStore.shared

    var body: some View {
        let room = live ? nil : store.rooms.first { $0.messages.contains { $0.handoff?.to == handoff.to && $0.handoff?.from == handoff.from } }
        let target = live ? (roomID.map { BotsRoute.room($0) } ?? BotsRoute.botPage(handoff.to))
                          : (room.map { BotsRoute.room($0.id) } ?? BotsRoute.botPage(handoff.to))
        NavigationLink(value: target) {
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

    /// Paired: every sheet here writes the desktop, or says where to do it. None changes the phone's copy.
    private var isLive: Bool { !Connection.shared.usesSampleData }

    @ViewBuilder
    private func content(_ team: BotTeam) -> some View {
        if isLive {
            liveContent(team)
        } else {
            sampleContent(team)
        }
    }

    @ViewBuilder
    private func liveContent(_ team: BotTeam) -> some View {
        switch which {
        case .instructions: BotTmInstructionsForm(team: team)
        case .memory: BotTmMemoryForm(team: team)
        case .chief: BotTmChiefForm(team: team)
        case .rename: BotTmRenameForm(team: team)
        case .delete: BotTmDeleteForm(team: team, after: after)
        case .manage, .settings, .models, .newTeam, .newRoom:
            SheetTitle(title: "Do this on your desktop", detail: "Adding or moving bots, and changing every member's settings at once, are done in Kairos on your desktop.")
            QuietButton(title: "Close") { dismiss() }
        }
    }

    @ViewBuilder
    private func sampleContent(_ team: BotTeam) -> some View {
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
              if !Connection.shared.usesSampleData {
                // Paired: a new team moves bots on the desktop; that stays there in this version.
                SheetTitle(title: "New team", detail: "Make a team in Kairos on your desktop. It shows here once it is made.")
                QuietButton(title: "Close") { dismiss() }
              } else {
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
              if !Connection.shared.usesSampleData {
                // Paired: rooms are made on the desktop until the rooms pass wires this sheet.
                SheetTitle(title: "New room", detail: "Make a room in Kairos on your desktop. It shows here once it is made.")
                QuietButton(title: "Close") { dismiss() }
              } else {
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
    let live = BotsTeamsLive.shared
    @State private var window = "Last 7 days"

    private var isLive: Bool { !Connection.shared.usesSampleData }

    var body: some View {
        if isLive { liveBody } else { sampleBody }
    }

    // MARK: Paired

    private var liveBody: some View {
        let days = window == "Last 30 days" ? 30 : 7
        let key = "\(teamID)|\(days)"
        let report = live.isCurrent ? live.reports[key] : nil
        let members = BotLossyList(report?.members)
        let produced = BotLossyList(report?.produced).items.filter { ($0.count ?? 0) > 0 }
        return BotsPage("Team report", subtitle: report?.team?.name ?? store.teams.first { $0.id == teamID }?.name ?? "", live: true) {
            GoldSegmented(items: ["Last 7 days", "Last 30 days"], selection: $window) { $0 }
            if let report {
                let totals = report.totals
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    tile("Runs", "\(totals?.runs ?? 0)")
                    tile("Failed", "\(totals?.failed ?? 0)")
                    tile("Tokens", Self.compact(totals?.tokens ?? 0))
                    tile("Spend", totals?.costUsd.map { String(format: "$%.2f", $0) } ?? "Unknown")
                }
                HintLine(text: (totals?.asked ?? 0) == 1 ? "The team asked you once." : "The team asked you \(totals?.asked ?? 0) times.", symbol: "hand.raised")
                if let missed = totals?.couldNotAsk, missed > 0 {
                    HintLine(text: missed == 1 ? "1 step did not run because nobody was there to ask." : "\(missed) steps did not run because nobody was there to ask.",
                             symbol: "exclamationmark.circle", color: Palette.goldText)
                }
                BotsSection(title: "What the team made") {
                    if produced.isEmpty { EmptyNote(text: "Nothing made in this window.", symbol: "doc.richtext") }
                    ForEach(Array(produced.enumerated()), id: \.offset) { index, item in
                        if index > 0 { RowLine(inset: 54) }
                        HStack(spacing: 12) {
                            Image(systemName: "doc.richtext").foregroundStyle(Palette.goldText).frame(width: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(item.label ?? "Made") · \(item.count ?? 0)").font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                                if let items = item.items, !items.isEmpty {
                                    Text(items.joined(separator: ", ")).font(KFont.ui(13)).foregroundStyle(Palette.inkFaint).lineLimit(2)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 50)
                    }
                }
                SectionLabel(text: "Members").padding(.horizontal, 4)
                if members.items.isEmpty { EmptyNote(text: "This team has no bots.", symbol: "person.3").kCard(radius: 20) }
                ForEach(Array(members.items.enumerated()), id: \.offset) { index, member in
                    liveMemberCard(member, index: index)
                }
                if members.skipped > 0 {
                    HintLine(text: members.skipped == 1 ? "1 member could not be read by this app." : "\(members.skipped) members could not be read by this app.", symbol: "info.circle")
                        .padding(.horizontal, 4)
                }
            } else {
                BotsLoadNote(state: live.shown(live.reportLoad[key]), waiting: "Reading the team report from your desktop.") {
                    Task { await live.loadReport(teamID, days: days) }
                }
            }
        }
        .task(id: "\(BotsStore.connectionKey)|\(days)") {
            live.followConnection()
            guard isLive else { return }
            await live.loadReport(teamID, days: days)
        }
    }

    private func liveMemberCard(_ member: BotTmReportMemberDTO, index: Int) -> some View {
        let bot = store.bot(member.botId)
        let last = member.last.map { [$0.what, $0.result].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") } ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                BotFace(bot: bot, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(member.name ?? bot.name).font(KFont.ui(16.5, .semibold)).foregroundStyle(Palette.ink)
                    Text(last.isEmpty ? "No runs in this window" : "Last: \(last)").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint).lineLimit(2)
                }
                Spacer()
            }
            HStack {
                stat("Runs", "\(member.runs ?? 0)")
                stat("Failed", "\(member.failed ?? 0)")
                stat("Spend", member.costUsd.map { String(format: "$%.2f", $0) } ?? "Unknown")
                stat("Asked you", "\(member.asked ?? 0)")
            }
            NavigationLink(value: BotsRoute.report(member.botId)) {
                Text("Open report").font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44).background(Palette.ink.opacity(0.1), in: Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .padding(14)
        .kCard(radius: 20)
        .arrives(index)
    }

    /// 48000 as "48K", 1400000 as "1.4M".
    static func compact(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", Double(value) / 1_000) }
        return "\(value)"
    }

    // MARK: Sample

    @ViewBuilder
    private var sampleBody: some View {
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
    @State private var pausing: BotTeam?
    let live = BotsTeamsLive.shared

    /// Paired: teams, pause switches and hand-offs are the desktop's. Sending to many bots, new rooms, new teams
    /// and moving bots stay on the desktop.
    private var isLive: Bool { !Connection.shared.usesSampleData }

    var body: some View {
        let unteamed = store.bots.filter { store.team(of: $0.id) == nil }
        BotsPage("Team map", live: isLive, trailing: {
            if !isLive {
                HStack(spacing: 8) {
                    GlassIconButton(symbol: "number", label: "New room") { newRoom = true }
                    GlassIconButton(symbol: "plus", label: "New team") { newTeam = true }
                }
            }
        }) {
            if isLive {
                HintLine(text: "Make teams and rooms, move bots, and send to several bots at once in Kairos on your desktop.", symbol: "desktopcomputer")
                    .padding(.horizontal, 4)
                BotsLoadNote(state: mapState, waiting: "Reading your teams from your desktop.") {
                    Task {
                        if store.rosterLoad != .loaded { await store.loadRoster() }
                        await live.loadMap(force: false)
                    }
                }
            } else {
                composer
            }
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
            if isLive {
                if live.mapReady { liveHandoffs }
            } else {
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
        }
        .task(id: BotsStore.connectionKey) {
            store.followConnection()
            live.followConnection()
            guard isLive else { return }
            if store.rosterLoad != .loaded { await store.loadRoster() }
            await live.loadIfNeeded()
        }
        .sheet(item: $pausing) { team in
            ConfirmSheet(title: "Pause \(team.name)?", detail: BotTmMap.pauseDetail, confirm: "Pause team") {
                live.setPaused(team.id, name: team.name, true, say: store.say)
            }
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

    /// Paired: reading until both the roster (teams and members) and the map (pause switches, hand-offs) are in.
    private var mapState: BotsLiveLoad {
        switch store.rosterLoad {
        case .loaded: return live.mapReady ? .loaded : live.shown(live.mapLoad)
        case .idle: return .loading
        default: return store.rosterLoad
        }
    }

    /// The hand-offs the desktop has going now, each opening its room or the bot it went to.
    private var liveHandoffs: some View {
        let rows = live.shownHandoffs.compactMap { edge in BotTmMap.handoff(edge).map { (handoff: $0, room: edge.roomId) } }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.snappy) { showHandoffs.toggle() }
            } label: {
                HStack {
                    Text("Handoffs \(rows.count)").font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: showHandoffs ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                }
                .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            if showHandoffs {
                if rows.isEmpty {
                    RowLine()
                    EmptyNote(text: "No hand-offs right now.", symbol: "arrow.left.arrow.right")
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    RowLine()
                    HandoffRow(handoff: row.handoff, live: true, roomID: row.room)
                }
            }
        }
        .kCard(radius: 20)
    }

    private func teamCard(_ team: BotTeam) -> some View {
        let paused = isLive ? live.paused(team.id) : team.paused
        let waits = isLive && live.waits(team.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                NavigationLink(value: BotsRoute.team(team.id)) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(team.name).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                        Text("\(team.members.count) bots\(paused ? " · paused" : "")").font(KFont.ui(12.5)).foregroundStyle(paused ? Palette.goldText : Palette.inkFaint)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.98))
                PillButton(title: paused ? "Resume team" : "Pause team", look: paused ? .filled : .plain) {
                    if !isLive {
                        store.setPaused(team.id, !team.paused)
                    } else if paused {
                        live.setPaused(team.id, name: team.name, false, say: store.say)
                    } else {
                        pausing = team
                    }
                }
                .disabled(waits)
                .opacity(waits ? 0.5 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            ForEach(team.members, id: \.self) { id in
                RowLine(inset: 62)
                botTile(store.bot(id), chief: team.chief == id)
            }
        }
        .kCard(radius: 20)
        .opacity(paused ? 0.85 : 1)
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
                    Text(isLive ? bot.model : store.settings(bot.id).model).font(KFont.ui(12)).foregroundStyle(Palette.inkDim)
                        .padding(.horizontal, 8).frame(minHeight: 24).background(Palette.ink.opacity(0.07), in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            Menu {
                Button { goto = .botPage(bot.id) } label: { Label("Chat and settings", systemImage: "bubble.left") }
                Button { goto = .report(bot.id) } label: { Label("Report for \(bot.name)", systemImage: "chart.bar.doc.horizontal") }
                // Paired: a bot's team is its desktop `section`; moving it stays on the desktop.
                if !isLive {
                    Menu("Move to team") {
                        ForEach(store.teams.filter { !$0.members.contains(bot.id) }) { team in
                            Button(team.name) { moving = (bot.id, team.id) }
                        }
                        if store.team(of: bot.id) != nil {
                            Button("Other bots") { moving = (bot.id, nil) }
                        }
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

    /// Paired: the desktop has no level above a team, so there is nothing to group or move.
    private var isLive: Bool { !Connection.shared.usesSampleData }

    var body: some View {
        if isLive { liveBody } else { sampleBody }
    }

    private var liveBody: some View {
        BotsPage("Departments", live: true) {
            HintLine(text: "Your desktop groups bots into teams only.", symbol: "info.circle")
                .padding(.horizontal, 4)
            if !store.teams.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(store.teams.enumerated()), id: \.element.id) { index, team in
                        if index > 0 { RowLine(inset: 54) }
                        NavigationLink(value: BotsRoute.team(team.id)) {
                            NavRow(title: team.name, symbol: "person.3", detail: "\(team.members.count) bots")
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .kCard(radius: 20)
            }
        }
    }

    @ViewBuilder
    private var sampleBody: some View {
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
                    FaceStack(ids: team.members, size: 34).fixedSize().frame(minWidth: 60, alignment: .leading)
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

// MARK: - Team sheets while paired

/// Team instructions on the desktop: read with their hash, saved with it. A change on the desktop keeps the typed text.
struct BotTmInstructionsForm: View {
    let team: BotTeam
    let live = BotsTeamsLive.shared
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// The desktop's text this form was filled from (or last told about).
    @State private var base: String?
    @State private var saving = false
    @State private var note: String?
    @State private var changed = false
    /// The text sent whose answer was lost: the next tap looks for it instead of sending.
    @State private var lookFirst: String?

    var body: some View {
        let read = live.isCurrent ? live.instructions[team.id] : nil
        let tooLong = text.utf8.count > 24_000
        VStack(alignment: .leading, spacing: 14) {
            SheetTitle(title: "Team instructions", detail: "Every bot in \(team.name) reads these.")
            if read == nil || base == nil {
                BotsLoadNote(state: live.shown(live.instructionsLoad[team.id]), waiting: "Reading the instructions from your desktop.") {
                    Task { await live.loadInstructions(team.id) }
                }
            } else {
                FieldCard(title: "Instructions", text: $text, placeholder: "How this team works", lines: 6...14)
                Text("\(text.utf8.count) / 24,000 bytes").font(KFont.ui(12.5)).foregroundStyle(tooLong ? Palette.danger : Palette.inkFaint)
                if let note { HintLine(text: note, symbol: "info.circle", color: Palette.goldText) }
                if changed, let desk = read?.text, desk != text, lookFirst == nil {
                    PillButton(title: "Use the text on your desktop", symbol: "arrow.down.doc", wide: true) {
                        text = desk
                        changed = false
                        note = nil
                    }
                    .disabled(saving)
                }
                GoldButton(title: lookFirst != nil ? "Look again" : (saving ? "Saving" : "Save instructions")) { save() }
                    .disabled(saving || (tooLong && lookFirst == nil))
                    .opacity(saving || (tooLong && lookFirst == nil) ? 0.5 : 1)
            }
        }
        .interactiveDismissDisabled(saving)
        .task(id: BotsStore.connectionKey) {
            live.followConnection()
            guard !Connection.shared.usesSampleData else { return }
            await live.loadInstructions(team.id)
        }
        .onAppear(perform: fill)
        .onChange(of: read) { fill() }
    }

    private func fill() {
        guard live.isCurrent, let read = live.instructions[team.id] else { return }
        let desk = read.text ?? ""
        guard let base else {
            text = desk
            self.base = desk
            return
        }
        // A later read found other text on the desktop: say so, keep what was typed.
        if desk != base && !saving && lookFirst == nil {
            self.base = desk
            if desk != text {
                changed = true
                note = "The instructions changed on your desktop. Your text is kept here. Saving now replaces what your desktop has."
            }
        }
    }

    private func save() {
        if let sent = lookFirst {
            saving = true
            Task { finish(await live.confirmInstructions(team.id, sent: sent), sent: sent) }
            return
        }
        guard text.utf8.count <= 24_000 else { return }
        if text == base && !changed { dismiss(); return }
        let sent = text
        saving = true
        Task { finish(await live.saveInstructions(team.id, text: sent), sent: sent) }
    }

    private func finish(_ outcome: BotTmOutcome, sent: String) {
        saving = false
        switch outcome {
        case .done(let words):
            lookFirst = nil
            base = sent
            changed = false
            if sent == text {
                store.say(words)
                dismiss()
            } else {
                note = "Your earlier text was saved. What you changed after that is not saved yet."
            }
        case .refused(let words):
            lookFirst = nil
            note = words
        case .changed(let words):
            lookFirst = nil
            changed = true
            base = live.instructions[team.id]?.text ?? base
            note = words
        case .unsure(let words):
            lookFirst = sent
            note = words
        }
    }
}

/// Team memory on the desktop: entries grouped by kind, add (accepted at once), delete after a confirm.
struct BotTmMemoryForm: View {
    let team: BotTeam
    let live = BotsTeamsLive.shared
    let store = BotsStore.shared
    @State private var kind = "decision"
    @State private var entryName = ""
    @State private var entryDetail = ""
    @State private var saving = false
    @State private var note: String?
    @State private var removing: BotTmMemoryEntryDTO?

    var body: some View {
        let entries = live.isCurrent ? live.memory[team.id] : nil
        let looking = live.addChecks[team.id] != nil
        VStack(alignment: .leading, spacing: 14) {
            SheetTitle(title: "Team memory", detail: "What the whole team remembers.")
            if let entries {
                ForEach(BotTmMap.kinds + ["other"], id: \.self) { group in
                    let rows = entries.filter { group == "other" ? !BotTmMap.kinds.contains($0.kind ?? "") : $0.kind == group }
                    if !rows.isEmpty {
                        BotsSection(title: BotTmMap.kindTitle(group)) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { RowLine() }
                                row(entry)
                            }
                        }
                    }
                }
                if entries.isEmpty { EmptyNote(text: "No team memories yet.", symbol: "brain").kCard(radius: 20) }
                if let skipped = live.skippedMemory[team.id], skipped > 0 {
                    HintLine(text: skipped == 1 ? "1 entry could not be read by this app." : "\(skipped) entries could not be read by this app.", symbol: "info.circle")
                }
                SectionLabel(text: "Add entry")
                GoldSegmented(items: BotTmMap.kinds, selection: $kind) { BotTmMap.kindTitle($0) }
                FieldCard(title: "Name", text: $entryName, placeholder: "Short name", limit: 120)
                FieldCard(title: "Detail", text: $entryDetail, placeholder: "What to remember", limit: 600, lines: 2...5)
                if let note { HintLine(text: note, symbol: "info.circle", color: Palette.goldText) }
                GoldButton(title: saving ? "Adding" : (looking ? "Look again" : "Add memory")) { add(looking: looking) }
                    .disabled(saving)
                    .opacity(saving ? 0.5 : 1)
            } else {
                BotsLoadNote(state: live.shown(live.memoryLoad[team.id]), waiting: "Reading the team's memory from your desktop.") {
                    Task { await live.loadMemory(team.id) }
                }
            }
        }
        .interactiveDismissDisabled(saving)
        .task(id: BotsStore.connectionKey) {
            live.followConnection()
            guard !Connection.shared.usesSampleData else { return }
            await live.loadMemory(team.id)
        }
        .sheet(item: $removing) { entry in
            ConfirmSheet(title: "Delete this memory?", detail: "\"\(entry.name ?? "This entry")\" is removed from what \(team.name) remembers.", confirm: "Delete") {
                live.deleteMemory(team.id, entry, say: store.say)
            }
        }
    }

    private func row(_ entry: BotTmMemoryEntryDTO) -> some View {
        let name = entry.name ?? ""
        let detail = entry.detail ?? ""
        let when = entry.createdAt.map { ChatFormat.listTime(Date(timeIntervalSince1970: $0)) } ?? ""
        let by = entry.sourceBotId.map { store.bot($0).name } ?? "you"
        let proposed = entry.status == "proposed"
        let busy = live.deleting.contains(entry.id)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.isEmpty ? name : "\(name): \(detail)").font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                Text(proposed ? "Suggested by \(by). Accept it in Kairos on your desktop." : "Added by \(by)\(when.isEmpty ? "" : ", \(when)")")
                    .font(KFont.ui(12.5)).foregroundStyle(proposed ? Palette.goldText : Palette.inkFaint)
            }
            Spacer()
            Button {
                removing = entry
            } label: {
                Image(systemName: "trash").foregroundStyle(Palette.danger).frame(width: 44, height: 44)
            }
            .disabled(busy || entry.revision == nil)
            .opacity(busy ? 0.4 : 1)
            .accessibilityLabel("Delete \(name)")
        }
        .padding(.leading, 14)
    }

    private func add(looking: Bool) {
        if looking {
            saving = true
            Task { finish(await live.confirmAdd(team.id)) }
            return
        }
        let name = BotTmMap.clean(entryName)
        let detail = BotTmMap.clean(entryDetail)
        guard !name.isEmpty, !detail.isEmpty, name.count <= 120, detail.count <= 600 else {
            Haptics.thud()
            note = "Give it a short name and a detail."
            return
        }
        saving = true
        Task { finish(await live.addMemory(team.id, kind: kind, name: name, detail: detail)) }
    }

    private func finish(_ outcome: BotTmOutcome) {
        saving = false
        switch outcome {
        case .done(let words):
            note = nil
            entryName = ""
            entryDetail = ""
            store.say(words)
        case .refused(let words), .changed(let words), .unsure(let words):
            note = words
        }
    }
}

/// Pick the team's Chief of Staff on the desktop, or none.
struct BotTmChiefForm: View {
    let team: BotTeam
    let live = BotsTeamsLive.shared
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var note: String?
    /// A choice whose answer was lost: the next tap looks for it instead of sending.
    @State private var unsure = false
    @State private var sent: String?

    var body: some View {
        let record = live.department(team.id)
        VStack(alignment: .leading, spacing: 14) {
            SheetTitle(title: "Chief of Staff", detail: "One Chief of Staff can coordinate this team. It needs a model that can use tools.")
            if let record {
                VStack(spacing: 0) {
                    ForEach(Array(team.members.enumerated()), id: \.element) { index, id in
                        if index > 0 { RowLine(inset: 62) }
                        Button {
                            pick(id, current: record.chiefBotId)
                        } label: {
                            HStack(spacing: 12) {
                                BotFace(bot: store.bot(id), size: 36)
                                Text(store.bot(id).name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                                Spacer()
                                if record.chiefBotId == id { Image(systemName: "crown.fill").foregroundStyle(Palette.goldText) }
                            }
                            .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                        .disabled(saving || unsure)
                    }
                }
                .kCard(radius: 20)
                if team.members.isEmpty { EmptyNote(text: "This team has no bots.", symbol: "person.3").kCard(radius: 20) }
                if let note { HintLine(text: note, symbol: "info.circle", color: Palette.goldText) }
                if unsure {
                    GoldButton(title: saving ? "Looking" : "Look again") { look() }
                        .disabled(saving)
                        .opacity(saving ? 0.5 : 1)
                } else if record.chiefBotId != nil {
                    PillButton(title: saving ? "Saving" : "Remove chief", look: .danger, wide: true) { pick(nil, current: record.chiefBotId) }
                        .disabled(saving)
                }
            } else {
                BotsLoadNote(state: live.shown(live.mapLoad), waiting: "Reading the team from your desktop.") {
                    Task { await live.loadMap(force: false) }
                }
            }
        }
        .interactiveDismissDisabled(saving)
    }

    private func pick(_ id: String?, current: String?) {
        guard !saving, !unsure else { return }
        if id == current { dismiss(); return }
        Haptics.tap()
        saving = true
        sent = id
        Task { finish(await live.setChief(team.id, botID: id)) }
    }

    private func look() {
        saving = true
        Task { finish(await live.confirmChief(team.id, sent: sent)) }
    }

    private func finish(_ outcome: BotTmOutcome) {
        saving = false
        switch outcome {
        case .done(let words):
            unsure = false
            Haptics.success()
            store.say(words)
            dismiss()
        case .refused(let words), .changed(let words):
            unsure = false
            note = words
        case .unsure(let words):
            unsure = true
            note = words
        }
    }
}

/// Rename the team on the desktop with the revision it was read at.
struct BotTmRenameForm: View {
    let team: BotTeam
    let live = BotsTeamsLive.shared
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var filled = false
    @State private var saving = false
    @State private var note: String?
    /// The name sent whose answer was lost: the next tap looks for it instead of sending.
    @State private var lookFirst: String?

    var body: some View {
        let record = live.department(team.id)
        VStack(alignment: .leading, spacing: 14) {
            SheetTitle(title: "Rename team", detail: "Every bot in the team moves to the new name. Your desktop waits until none of them is working.")
            if record == nil {
                BotsLoadNote(state: live.shown(live.mapLoad), waiting: "Reading the team from your desktop.") {
                    Task { await live.loadMap(force: false) }
                }
            } else {
                FieldCard(title: "Team name", text: $text, placeholder: "Team name", limit: 60)
                if let note { HintLine(text: note, symbol: "info.circle", color: Palette.goldText) }
                GoldButton(title: lookFirst != nil ? (saving ? "Looking" : "Look again") : (saving ? "Saving" : "Save")) { save() }
                    .disabled(saving)
                    .opacity(saving ? 0.5 : 1)
            }
        }
        .interactiveDismissDisabled(saving)
        .onAppear(perform: fill)
        .onChange(of: record?.name) { fill() }
    }

    private func fill() {
        guard !filled, let record = live.department(team.id) else { return }
        filled = true
        text = record.name ?? team.name
    }

    private func save() {
        if let sent = lookFirst {
            saving = true
            Task { finish(await live.confirmRename(team.id, sent: sent), sent: sent) }
            return
        }
        let name = BotTmMap.clean(text)
        guard !name.isEmpty, name.count <= 60 else { note = "Use a team name of 1 to 60 characters."; return }
        if name == live.department(team.id)?.name { dismiss(); return }
        saving = true
        Task { finish(await live.rename(team.id, to: name), sent: name) }
    }

    private func finish(_ outcome: BotTmOutcome, sent: String) {
        saving = false
        switch outcome {
        case .done(let words):
            lookFirst = nil
            if BotTmMap.clean(text) == sent {
                store.say(words)
                dismiss()
            } else {
                note = "The team is now \(sent). What you typed after that is not saved yet."
            }
        case .refused(let words), .changed(let words):
            lookFirst = nil
            note = words
        case .unsure(let words):
            lookFirst = sent
            note = words
        }
    }
}

/// Delete the team on the desktop. The sheet is the confirm; it stays until the outcome is known.
struct BotTmDeleteForm: View {
    let team: BotTeam
    var after: () -> Void
    let live = BotsTeamsLive.shared
    let store = BotsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @State private var note: String?
    /// A delete whose answer was lost: the next tap looks instead of sending.
    @State private var mustLook = false

    var body: some View {
        let off = deleting || (!mustLook && live.waits(team.id))
        VStack(spacing: 16) {
            SheetTitle(title: "Delete \(team.name)?", detail: Self.detail(team.members.count))
            if let note { HintLine(text: note, symbol: "info.circle", color: Palette.goldText) }
            PillButton(title: mustLook ? (deleting ? "Looking" : "Look again") : (deleting ? "Deleting" : "Delete team"), look: .danger, wide: true) { act() }
                .disabled(off)
                .opacity(off ? 0.5 : 1)
            QuietButton(title: "Cancel") { dismiss() }
                .disabled(deleting)
        }
        .interactiveDismissDisabled(deleting)
    }

    /// What the desktop does on delete (services/bot_departments.py: delete clears every member's section).
    static func detail(_ count: Int) -> String {
        let who: String
        switch count {
        case 0: who = "The team goes."
        case 1: who = "Its bot leaves the team and is in no team."
        default: who = "Its \(count) bots leave the team and are in no team."
        }
        return who + " They keep their conversations and routines. The team's instructions and memory stop being used. Your desktop refuses while one of its bots is working."
    }

    private func act() {
        guard !deleting else { return }
        Haptics.thud()
        deleting = true
        let look = mustLook
        Task {
            let outcome = look ? await live.confirmDelete(team.id) : await live.deleteTeam(team.id)
            deleting = false
            switch outcome {
            case .done(let words):
                mustLook = false
                store.say(words)
                dismiss()
                after()
            case .refused(let words), .changed(let words):
                mustLook = false
                note = words
            case .unsure(let words):
                mustLook = true
                note = words
            }
        }
    }
}
