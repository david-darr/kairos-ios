import SwiftUI

/// The Settings half of a bot's panel: every part of the bot, as rows that open pages.
struct BotSettingsList: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared
    var routinesLive = BotsRoutinesLive.shared

    var body: some View {
        let bot = store.bot(botID)
        let s = store.settings(botID)
        let paired = live.active
        let agent = paired ? (live.record(botID) ?? store.details[botID]?.agent) : nil
        VStack(alignment: .leading, spacing: 18) {
            if store.liveMode {
                liveGlance(bot)
                HintLine(text: "Memory, skills, what it can reach, conversations and usage are not connected to your desktop yet. They show sample data.", symbol: "info.circle")
                    .padding(.horizontal, 4)
            } else {
                glance(bot, s)
            }

            group("How it thinks", [
                row(.model, "Model and effort", "cpu", value: paired ? Self.liveModelLine(agent) : "\(s.model) · \(s.effort.title)"),
                row(.approval, "Approval", "checkmark.shield", value: paired ? agent.map { BotsStore.liveApproval($0)?.title ?? "Custom" } : s.approval.title),
                row(.limits, "Limits", "gauge.with.dots.needle.33percent", value: paired ? Self.liveLimitsLine(agent) : (s.botOn ? "\(s.runsPerDay) runs a day" : "Off")),
            ])

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "What it does on its own").padding(.horizontal, 4)
                VStack(spacing: 0) {
                    NavigationLink(value: BotsRoute.routines(botID)) {
                        NavRow(title: "Routines and triggers", symbol: "clock.arrow.circlepath", value: routinesValue(paired))
                    }
                    RowLine(inset: 54)
                    NavigationLink(value: BotsRoute.calendar(botID)) {
                        NavRow(title: "Automation calendar", symbol: "calendar.day.timeline.left")
                    }
                }
                .buttonStyle(PressStyle(scale: 0.98))
                .kCard(radius: 20)
            }

            group("What it knows", [
                row(.memory, "Memory", "brain", value: s.useMemory ? "\(s.notes.count) notes" : "Off"),
                row(.aboutYou, "About you", "person.text.rectangle", value: nil),
                row(.skills, "Skills", "bolt", value: "\(s.skills.filter { $0.state == .on }.count) on"),
                row(.instructions, "Standing instructions", "text.quote", value: nil),
            ])

            group("What it can reach", [
                row(.access, "Access and grants", "key", value: "\(s.grants.filter { $0.level != .off }.count) apps"),
                row(.connections, "Connections", "link", value: "\(store.apps.filter { $0.state == .connected }.count)"),
                row(.browser, "Browser profiles", "globe", value: s.browserEnabled ? s.browserProfile : "Off"),
            ])

            group("Talking to you", [
                row(.voice, "Voice and calls", "waveform", value: paired ? Self.liveVoiceLine(agent, voices: live.voices) : s.voice),
                row(.delivery, "Where it reports", "paperplane", value: paired ? Self.liveChannelLine(agent, channels: live.channels) : s.reportTo),
                row(.conversations, "Conversations and folders", "bubble.left.and.bubble.right", value: "\(s.conversations.filter { !$0.archived }.count)"),
            ])

            group("Usage", [
                row(.usage, "Usage and plan", "chart.bar", value: "\(s.runsToday) of \(s.runsPerDay) today"),
            ])

            group("Who it is", [
                row(.look, "Look and name", "paintbrush", value: bot.isKip ? "Kip" : bot.name),
                row(.history, "History", "clock", value: nil),
            ])

            if let team = store.team(of: botID) {
                VStack(spacing: 0) {
                    NavigationLink(value: BotsRoute.team(team.id)) {
                        NavRow(title: "Team", symbol: "person.3", detail: store.chiefs.contains(botID) ? "Chief of Staff" : nil, value: team.name)
                    }
                }
                .buttonStyle(PressStyle(scale: 0.98))
                .kCard(radius: 20)
            }
        }
        .task(id: BotsSettingsLive.connectionKey) {
            live.followConnection()
            guard live.active else { return }
            // Read each time the list appears or the connection becomes ready: never a first read kept as fact.
            await live.loadRecord(botID)
            await routinesLive.loadIfNeeded()
        }
    }

    /// The routine and trigger count: the desktop's once both lists are read, none until then.
    private func routinesValue(_ paired: Bool) -> String? {
        guard paired else {
            return "\(store.routines(for: botID).count + store.triggers.filter { $0.botID == botID }.count)"
        }
        guard routinesLive.routinesReady, routinesLive.triggersReady else { return nil }
        return "\(routinesLive.routines(for: botID).count + routinesLive.shownTriggers.filter { $0.botID == botID }.count)"
    }

    static func liveModelLine(_ agent: AgentDTO?) -> String? {
        guard let agent else { return nil }
        let model = BotsStore.liveModel(agent)
        guard let effort = agent.modelEffort, !effort.isEmpty else { return model }
        return "\(model) · \(BotSetWords.effort(effort))"
    }

    static func liveLimitsLine(_ agent: AgentDTO?) -> String? {
        guard let agent else { return nil }
        if agent.enabled == false { return "Off" }
        return "\(agent.dailyRunCap ?? 12) runs a day"
    }

    static func liveVoiceLine(_ agent: AgentDTO?, voices: [BotSetVoiceDTO]) -> String? {
        guard let agent else { return nil }
        guard let id = agent.voiceId, !id.isEmpty else { return "Default voice" }
        return voices.first { $0.id == id }?.name ?? id
    }

    static func liveChannelLine(_ agent: AgentDTO?, channels: [TaskChannelDTO]) -> String? {
        guard let agent else { return nil }
        guard let id = agent.deliverToChannel, !id.isEmpty else { return "In the app" }
        return channels.first { $0.id == id }?.label ?? id
    }

    private struct Entry: Identifiable {
        let page: BotSettingsPage
        let title: String
        let symbol: String
        let value: String?
        var id: BotSettingsPage { page }
    }

    private func row(_ page: BotSettingsPage, _ title: String, _ symbol: String, value: String?) -> Entry {
        Entry(page: page, title: title, symbol: symbol, value: value)
    }

    private func group(_ title: String, _ entries: [Entry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowLine(inset: 54) }
                    NavigationLink(value: BotsRoute.settings(botID, entry.page)) {
                        NavRow(title: entry.title, symbol: entry.symbol, value: entry.value)
                    }
                }
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .kCard(radius: 20)
        }
    }

    /// "At a glance": who it is, what it does, what it reaches, what it will not do.
    private func glance(_ bot: Bot, _ s: BotSettings) -> some View {
        NavigationLink(value: BotsRoute.settings(botID, .overview)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: "At a glance")
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                }
                glanceLine("person", "\(bot.role). \(s.approval.hint)")
                glanceLine("clock.arrow.circlepath", "\(store.routines(for: botID).count) routines, \(store.work.filter { $0.botID == botID && $0.state == .working }.count) tasks running")
                glanceLine("key", s.grants.filter { $0.level != .off }.map(\.app).joined(separator: ", ").isEmpty ? "It cannot reach any apps yet." : "Reaches " + s.grants.filter { $0.level != .off }.map(\.app).joined(separator: ", "))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 20, raised: true)
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }

    /// "At a glance" from the paired desktop (GET /api/agents/{id}).
    private func liveGlance(_ bot: Bot) -> some View {
        let detail = store.details[botID]
        let state = store.detailLoad[botID] ?? .idle
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "At a glance")
            if let detail, let agent = detail.agent {
                glanceLine("person", "\(bot.role). \(BotsStore.liveApproval(agent)?.hint ?? "It follows its own approval rules.")")
                glanceLine("clock.arrow.circlepath", Self.workLine(detail, agent))
                glanceLine("key", Self.reachLine(agent))
                if let now = agent.statusDetail?.trimmingCharacters(in: .whitespacesAndNewlines), !now.isEmpty {
                    glanceLine("bolt", now)
                }
            } else if case .failed = state {
                glanceLine("exclamationmark.circle", "This bot could not be read. Use Try again above.")
            } else {
                glanceLine("arrow.down.circle", "Reading this bot from your desktop.")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 20, raised: true)
    }

    private static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    private static func workLine(_ detail: AgentDetailDTO, _ agent: AgentDTO) -> String {
        let routines = count(detail.goals?.count ?? 0, "routine", "routines")
        let cards = count(detail.cards?.count ?? 0, "work card", "work cards")
        let runs = count(agent.runsToday ?? 0, "run today", "runs today")
        return "\(routines), \(cards), \(runs)"
    }

    private static func reachLine(_ agent: AgentDTO) -> String {
        let apps = agent.integrationIds?.count ?? 0
        let browser = agent.browserEnabled == true
        switch (apps, browser) {
        case (0, false): return "It cannot reach any apps yet."
        case (0, true): return "It can use the browser."
        default:
            let line = "It can use " + count(apps, "connected app", "connected apps")
            return browser ? line + " and the browser." : line + "."
        }
    }

    private func glanceLine(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.goldText).frame(width: 18)
            Text(text).font(KFont.ui(14.5, relativeTo: .subheadline)).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
        }
    }
}

/// One Settings page for one bot.
struct BotSettingsScreen: View {
    let botID: String
    let page: BotSettingsPage

    var body: some View {
        switch page {
        case .overview: OverviewSettings(botID: botID)
        case .model: ModelSettings(botID: botID)
        case .approval: ApprovalSettings(botID: botID)
        case .voice: VoiceSettings(botID: botID)
        case .delivery: DeliverySettings(botID: botID)
        case .memory: MemorySettings(botID: botID)
        case .aboutYou: AboutYouSettings()
        case .skills: SkillsSettings(botID: botID)
        case .skillLibrary: SkillLibrarySettings(botID: botID)
        case .access: AccessSettings(botID: botID)
        case .connections: ConnectionsSettings()
        case .browser: BrowserSettings(botID: botID)
        case .usage: UsageSettings(botID: botID)
        case .limits: LimitsSettings(botID: botID)
        case .conversations: ConversationsSettings(botID: botID)
        case .look: BotLookScreen(botID: botID)
        case .instructions: InstructionsSettings(botID: botID)
        case .history: HistorySettings(botID: botID)
        }
    }
}

// MARK: - Overview

struct OverviewSettings: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared

    var body: some View {
        if live.active {
            BotSetOverviewScreen(botID: botID)
        } else {
            sample
        }
    }

    @ViewBuilder private var sample: some View {
        let bot = store.bot(botID)
        let s = store.settings(botID)
        BotsPage("At a glance", subtitle: bot.name) {
            BotsSection(title: "Who") {
                line("\(bot.name), \(bot.role.lowercased()). \(s.introduction)")
            }
            BotsSection(title: "What it does") {
                line("\(store.routines(for: botID).count) routines, \(store.triggers.filter { $0.botID == botID }.count) triggers, \(store.work.filter { $0.botID == botID && $0.state == .working }.count) open tasks.")
            }
            BotsSection(title: "What it can reach") {
                ForEach(Array(s.grants.enumerated()), id: \.element.id) { index, grant in
                    if index > 0 { RowLine(inset: 54) }
                    HStack(spacing: 12) {
                        Image(systemName: grant.symbol).foregroundStyle(Palette.goldText).frame(width: 26)
                        Text(grant.app).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(grant.level.rawValue).font(KFont.ui(14)).foregroundStyle(Palette.inkFaint)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                }
            }
            BotsSection(title: "What it will not do") {
                line(s.approval == .full ? "Nothing is held back." : "It will not \(s.approval == .ask ? "change or run anything" : "send messages or spend money") without asking you first.")
            }
            BotsSection(title: "Recent runs") {
                ForEach(Array(BotsSample.runs(for: bot).prefix(3).enumerated()), id: \.element.id) { index, run in
                    if index > 0 { RowLine() }
                    HStack {
                        Text(run.title).font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(run.outcome) · \(run.when)").font(KFont.ui(13.5)).foregroundStyle(Palette.inkFaint)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                }
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(KFont.ui(15.5))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
    }
}

// MARK: - Model and effort

struct ModelSettings: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared

    var body: some View {
        if live.active {
            BotSetModelScreen(botID: botID)
        } else {
            sample
        }
    }

    @ViewBuilder private var sample: some View {
        let binding = store.binding(botID)
        let s = binding.wrappedValue
        BotsPage("Model and effort", subtitle: "\(s.connection) · \(s.model) · \(s.effort.title)") {
            BotsSection {
                MenuRow(title: "Connection", symbol: "link", options: ["Claude (default)", "Codex", "This PC"], selection: Binding(
                    get: { s.connection },
                    set: { value in
                        binding.wrappedValue.connection = value
                        let first = BotsSample.models.first { $0.source.contains(value == "Codex" ? "Codex" : (value == "This PC" ? "PC" : "Claude")) }
                        binding.wrappedValue.model = first?.name ?? s.model
                        store.say("Model reset for the new connection")
                    }
                ))
            }

            BotsSection(title: "Model") {
                ForEach(Array(BotsSample.models.enumerated()), id: \.element.id) { index, model in
                    if index > 0 { RowLine() }
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) { binding.wrappedValue.model = model.name }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink)
                                Text("\(model.source) · \(model.about)").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                            }
                            Spacer()
                            if model.name == s.model {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.goldText)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                    .accessibilityAddTraits(model.name == s.model ? .isSelected : [])
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Effort").padding(.horizontal, 4)
                GoldSegmented(items: Effort.allCases, selection: binding.effort) { $0.title }
                Text("Higher effort thinks longer and uses more of your plan.")
                    .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).padding(.horizontal, 6)
            }

            BotsSection(title: "When it is busy") {
                MenuRow(title: "Keep warm", options: ["Follow default", "On", "Off"], selection: binding.keepWarm)
            }

            BotsSection(title: "If this model fails", footer: "It tries these in order, up to five.") {
                ForEach(Array(s.fallbacks.enumerated()), id: \.offset) { index, name in
                    if index > 0 { RowLine() }
                    HStack {
                        Text("\(index + 1). \(name)").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                        Spacer()
                        Button {
                            Haptics.tap()
                            _ = withAnimation(Motion.snappy) { binding.wrappedValue.fallbacks.remove(at: index) }
                        } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 20)).foregroundStyle(Palette.danger)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Remove \(name)")
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 6)
                }
                if s.fallbacks.count < 5 {
                    if !s.fallbacks.isEmpty { RowLine() }
                    Menu {
                        ForEach(BotsSample.models.filter { $0.name != s.model && !s.fallbacks.contains($0.name) }) { model in
                            Button(model.name) {
                                withAnimation(Motion.snappy) { binding.wrappedValue.fallbacks.append(model.name) }
                            }
                        }
                    } label: {
                        Label("Add a fallback", systemImage: "plus")
                            .font(KFont.ui(16, .medium))
                            .foregroundStyle(Palette.goldText)
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                }
            }

            HStack(spacing: 10) {
                Text("2 conversations use a different model.").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                Spacer()
                PillButton(title: "Switch them too") {
                    Haptics.success()
                    store.say("2 conversations now use \(s.model)")
                }
            }
            .padding(14)
            .kCard(radius: 18)
        }
    }
}

// MARK: - Approval

struct ApprovalSettings: View {
    let botID: String
    let store = BotsStore.shared
    @State private var scope = "The whole bot"
    @State private var raising: ApprovalLevel?
    @State private var newCommand = ""
    var live = BotsSettingsLive.shared

    var body: some View {
        if live.active {
            BotSetApprovalScreen(botID: botID)
        } else {
            sample
        }
    }

    @ViewBuilder private var sample: some View {
        let binding = store.binding(botID)
        let s = binding.wrappedValue
        let current = scope == "This conversation" ? (s.conversationApproval ?? s.approval) : s.approval
        BotsPage("Approval", subtitle: "Before it acts") {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Change it for").padding(.horizontal, 4)
                GoldSegmented(items: ["This conversation", "The whole bot"], selection: $scope) { $0 }
                if scope == "This conversation" {
                    HStack {
                        Text(s.conversationApproval == nil ? "This conversation follows the bot (\(s.approval.title))." : "This conversation: \(current.title)")
                            .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        Spacer()
                        if s.conversationApproval != nil {
                            PillButton(title: "Follow the bot again") {
                                withAnimation(Motion.snappy) { binding.wrappedValue.conversationApproval = nil }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            VStack(spacing: 10) {
                ForEach(ApprovalLevel.allCases, id: \.self) { level in
                    levelCard(level, current: current)
                }
            }

            HintLine(text: "Lowering a level applies at once. Raising one asks you to confirm here.", symbol: "info.circle")

            BotsSection(title: "Messages outside the app", footer: s.approval == .full ? "At Full the allowance does not apply. Ringing, calling, messaging or texting you never asks." : "Ringing, calling, messaging or texting you never asks.") {
                GoldSegmented(items: ["Ask", "Allow"], selection: Binding(
                    get: { s.outsideAllow ? "Allow" : "Ask" },
                    set: { binding.wrappedValue.outsideAllow = $0 == "Allow" }
                )) { $0 }
                .padding(8)
                if s.outsideAllow {
                    RowLine()
                    StepperRow(title: "Outside messages per day", value: binding.outsidePerDay, range: 1...1000, step: 5)
                    RowLine()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(s.outsideUsed) of \(s.outsidePerDay) used today. \(max(0, s.outsidePerDay - s.outsideUsed)) left.")
                            .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        MeterBar(fraction: Double(s.outsideUsed) / Double(max(1, s.outsidePerDay)))
                    }
                    .padding(14)
                } else {
                    RowLine()
                    Text("It asks before each outside message. Allowance if you let it send: \(s.outsidePerDay) a day.")
                        .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        .padding(14)
                }
            }

            BotsSection(title: "Always allowed", footer: "Commands you chose \"Always allow\" for. Remove one to be asked again.") {
                if s.alwaysAllowed.isEmpty {
                    EmptyNote(text: "Nothing is always allowed.", symbol: "checkmark.shield")
                }
                ForEach(Array(s.alwaysAllowed.enumerated()), id: \.offset) { index, command in
                    if index > 0 { RowLine() }
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(command).font(.system(size: 15, design: .monospaced)).foregroundStyle(Palette.ink)
                            Text("In the shop-site folder").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        PillButton(title: "Remove", look: .danger) {
                            _ = withAnimation(Motion.snappy) { binding.wrappedValue.alwaysAllowed.remove(at: index) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
            }
        }
        .sheet(item: $raising) { level in
            RaiseLevelSheet(botName: store.bot(botID).name, from: current, to: level) {
                apply(level)
            }
        }
    }

    private func levelCard(_ level: ApprovalLevel, current: ApprovalLevel) -> some View {
        let on = level == current
        return Button {
            Haptics.select()
            if level.rank > current.rank {
                raising = level
            } else {
                apply(level)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: level.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(on ? Palette.onGold : Palette.goldText)
                    .frame(width: 40, height: 40)
                    .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(level.title).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                        if level.rank > current.rank {
                            Text("Confirm to raise").font(KFont.ui(12, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                        }
                    }
                    Text(level.hint).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Palette.goldText : Palette.inkFaint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Palette.surfaceRaised : Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on ? Palette.gold : Palette.line, lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func apply(_ level: ApprovalLevel) {
        let binding = store.binding(botID)
        withAnimation(Motion.snappy) {
            if scope == "This conversation" {
                binding.wrappedValue.conversationApproval = level
            } else {
                binding.wrappedValue.approval = level
            }
        }
        store.say("Approval is now \(level.title)")
    }
}

/// Raising a level is confirmed on the phone. Full needs a swipe up.
struct RaiseLevelSheet: View {
    let botName: String
    let from: ApprovalLevel
    let to: ApprovalLevel
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FittedSheet(estimate: 460) {
            VStack(spacing: 18) {
                SheetTitle(title: "Raise to \(to.title)?", detail: "\(botName) goes from \(from.title) to \(to.title). \(to.hint)")
                Image(systemName: to.symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 76, height: 76)
                    .kGlass(Circle())
                if to == .full {
                    SwipeToConfirm(title: "Swipe up to give full access") {
                        action()
                        Task {
                            try? await Task.sleep(for: .seconds(0.5))
                            dismiss()
                        }
                    }
                } else {
                    GoldButton(title: "Raise to \(to.title)") {
                        Haptics.success()
                        action()
                        dismiss()
                    }
                }
                QuietButton(title: "Keep \(from.title)") { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Voice and calls

struct VoiceSettings: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared

    var body: some View {
        if live.active {
            BotSetVoiceScreen(botID: botID)
        } else {
            sample
        }
    }

    @ViewBuilder private var sample: some View {
        let binding = store.binding(botID)
        BotsPage("Voice and calls") {
            BotsSection(title: "Voice") {
                MenuRow(title: "Voice", symbol: "waveform", options: BotsSample.voices, selection: binding.voice)
                RowLine(inset: 54)
                MenuRow(title: "Voice provider", symbol: "speaker.wave.2", options: ["Same as the Voice", "Device voice", "The Voice's engine"], selection: binding.voiceProvider)
                RowLine(inset: 54)
                ToggleRow(title: "Speak its replies", detail: "It reads each reply aloud in its voice.", symbol: "text.bubble", isOn: binding.speakReplies)
            }
            BotsSection(title: "Calls") {
                MenuRow(title: "Call mode", symbol: "phone", options: ["Same as Settings", "Local", "Realtime"], selection: binding.callMode)
                RowLine(inset: 54)
                MenuRow(title: "Live voice", symbol: "person.wave.2", options: BotsSample.liveVoices, selection: binding.liveVoice)
                RowLine(inset: 54)
                ToggleRow(title: "Read typed replies", detail: "Text you type during a call is spoken into it.", symbol: "keyboard", isOn: binding.readTypedReplies)
                RowLine()
                StepperRow(title: "End an idle call after", value: binding.idleEndMinutes, range: 1...60, unit: "min")
            }
            BotsSection(title: "Alerts") {
                ToggleRow(title: "Tell me when it needs me", detail: "A notification when it waits for an answer or an OK.", symbol: "bell.badge", isOn: binding.tellMeWhenNeeded)
            }
        }
    }
}

// MARK: - Delivery

struct DeliverySettings: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared

    var body: some View {
        if live.active {
            BotSetDeliveryScreen(botID: botID)
        } else {
            sample
        }
    }

    @ViewBuilder private var sample: some View {
        let binding = store.binding(botID)
        BotsPage("Where it reports") {
            BotsSection(footer: "Where its reports and questions reach you.") {
                MenuRow(title: "Report to", symbol: "paperplane", options: BotsSample.channels, selection: binding.reportTo)
            }
            BotsSection(title: "Channels (2 connected)") {
                channel("Telegram", true)
                RowLine(inset: 54)
                channel("Email", true)
                RowLine(inset: 54)
                channel("Text message", false)
            }
            if binding.wrappedValue.reportTo == "Text message" {
                HintLine(text: "Text message is not connected yet, so reports stay in the app.", symbol: "exclamationmark.triangle", color: Palette.goldText)
            }
        }
    }

    private func channel(_ name: String, _ connected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left").foregroundStyle(Palette.goldText).frame(width: 26)
            Text(name).font(KFont.ui(16)).foregroundStyle(Palette.ink)
            Spacer()
            StateTag(text: connected ? "Connected" : "Not connected yet", color: connected ? Palette.success : Palette.inkFaint)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}

// MARK: - Limits

struct LimitsSettings: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared

    var body: some View {
        if live.active {
            BotSetLimitsScreen(botID: botID)
        } else {
            sample
        }
    }

    @ViewBuilder private var sample: some View {
        let binding = store.binding(botID)
        let s = binding.wrappedValue
        BotsPage("Limits") {
            BotsSection(footer: s.botOn ? nil : "Off, it takes no new work and its routines do not run.") {
                ToggleRow(title: "This bot is on", symbol: "power", isOn: binding.botOn)
            }
            BotsSection(title: "Runs") {
                StepperRow(title: "Runs per day", value: binding.runsPerDay, range: 1...200)
                RowLine()
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(s.runsToday) of \(s.runsPerDay) daily runs used. \(s.runsToday >= s.runsPerDay ? "It is done for today." : "\(s.runsPerDay - s.runsToday) left today.")")
                        .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                    MeterBar(fraction: Double(s.runsToday) / Double(max(1, s.runsPerDay)))
                }
                .padding(14)
            }
            BotsSection(title: "Monthly spend cap", footer: "List-price equivalent, not billed.") {
                ToggleRow(title: "Use a cap", isOn: Binding(
                    get: { s.monthlyCap != nil },
                    set: { binding.wrappedValue.monthlyCap = $0 ? 25 : nil }
                ))
                if let cap = s.monthlyCap {
                    RowLine()
                    StepperRow(title: "Cap in USD", value: Binding(get: { cap }, set: { binding.wrappedValue.monthlyCap = $0 }), range: 1...1000, step: 5)
                    RowLine()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(format: "$%.2f", s.spentThisMonth) + " this month of $\(cap)")
                            .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        MeterBar(fraction: s.spentThisMonth / Double(cap))
                    }
                    .padding(14)
                }
            }
        }
    }
}

// MARK: - Standing instructions

struct InstructionsSettings: View {
    let botID: String
    let store = BotsStore.shared
    @State private var text = ""
    @State private var intro = ""
    @State private var loaded = false
    var live = BotsSettingsLive.shared

    var body: some View {
        if live.active {
            BotSetInstructionsScreen(botID: botID)
        } else {
            sample
        }
    }

    @ViewBuilder private var sample: some View {
        let binding = store.binding(botID)
        BotsPage("Standing instructions") {
            FieldCard(title: "Standing instructions", text: $text, placeholder: "How it should work, always", limit: 24_000, lines: 6...14)
            FieldCard(title: "Introduction", text: $intro, placeholder: "A short line about who it is.", limit: 4_000, lines: 2...5)
            BotsSection(title: "Reply style") {
                GoldSegmented(items: ["Default", "Conversational"], selection: binding.replyStyle) { $0 }.padding(8)
            }
            GoldButton(title: "Save instructions") {
                binding.wrappedValue.standingInstructions = text
                binding.wrappedValue.introduction = intro
                binding.wrappedValue.history.insert(HistoryChange(who: "You", what: "changed the standing instructions", when: "just now"), at: 0)
                Haptics.success()
                store.say("Instructions saved")
            }
            .disabled(text == binding.wrappedValue.standingInstructions && intro == binding.wrappedValue.introduction)
            NavigationLink(value: BotsRoute.settings(botID, .history)) {
                Text("See how this changed").font(KFont.ui(15, .medium)).foregroundStyle(Palette.goldText).frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            text = binding.wrappedValue.standingInstructions
            intro = binding.wrappedValue.introduction
        }
    }
}

// MARK: - History

struct HistorySettings: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared

    var body: some View {
        if live.active {
            BotSetHistoryScreen(botID: botID)
        } else {
            sample
        }
    }

    @ViewBuilder private var sample: some View {
        let binding = store.binding(botID)
        let changes = binding.wrappedValue.history
        BotsPage("History", subtitle: "Settings version \(changes.count + 3)") {
            if changes.isEmpty {
                EmptyNote(text: "Nothing has changed since history started.", symbol: "clock").kCard(radius: 20)
            } else {
                BotsSection(title: "Changes") {
                    ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                        if index > 0 { RowLine() }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(change.who) \(change.what)")
                                    .font(KFont.ui(15.5)).foregroundStyle(change.undone ? Palette.inkFaint : Palette.ink)
                                    .strikethrough(change.undone)
                                Text(change.when).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                            }
                            Spacer()
                            PillButton(title: change.undone ? "Undone" : "Undo") {
                                guard !change.undone else { return }
                                Haptics.tap()
                                withAnimation(Motion.snappy) { binding.wrappedValue.history[index].undone = true }
                                store.say("Change undone")
                            }
                            .disabled(change.undone)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
            }
            HintLine(text: "Created October 2. Earlier instructions stay readable here.")
        }
    }
}

// MARK: - Paired with a desktop

/// Plain words for the desktop's values.
nonisolated enum BotSetWords {
    static func effort(_ value: String) -> String {
        Effort(rawValue: value)?.title ?? value.prefix(1).uppercased() + value.dropFirst()
    }

    static let callModes: [(id: String, title: String)] = [
        ("turns", "Same as Settings"), ("local", "Local"), ("live", "Live"), ("realtime", "Realtime"),
    ]

    static let keepWarm: [(id: String, title: String)] = [("follow", "Follow default"), ("on", "On"), ("off", "Off")]

    static func field(_ field: String?) -> String {
        switch field ?? "" {
        case "soul", "instructions": return "the standing instructions"
        case "blurb": return "the introduction"
        case "role": return "the job"
        case "name": return "the name"
        case "avatar", "color": return "the look"
        case "endpoint_id": return "the connection"
        case "model_override": return "the model"
        case "model_effort": return "the effort"
        case "fallback": return "the fallback models"
        case "cache_keep_warm": return "keep warm"
        case "approval_mode": return "approval"
        case "outbound": return "outside messages"
        case "enabled": return "whether it is on"
        case "daily_run_cap": return "runs per day"
        case "deliver_to_channel": return "where it reports"
        case "voice_id": return "the voice"
        case "call_mode": return "the call mode"
        case "speak_replies": return "speaking replies"
        case "notifications": return "alerts"
        case "reply_style": return "the reply style"
        case let other: return "the " + other.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func actor(_ actor: String?) -> String {
        switch actor ?? "" {
        case "user": return "You"
        case "bot": return "The bot"
        case "file": return "A file edit"
        case "import": return "An import"
        default: return "Kairos"
        }
    }

    static func when(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.relative(presentation: .named))
    }
}

/// Settings > At a glance, from GET /api/agents/{id}/overview.
private struct BotSetOverviewScreen: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared

    var body: some View {
        let bot = store.bot(botID)
        let overview = live.isCurrent ? live.overviews[botID] : nil
        BotsPage("At a glance", subtitle: bot.name, live: true) {
            BotsLoadNote(state: live.shown(live.overviewLoad[botID])) { Task { await live.loadOverview(botID) } }
            if let overview {
                BotsSection(title: "Who") {
                    line(whoLine(overview.who, fallback: bot.name))
                }
                let does = overview.does
                let routines = BotSetWire.items(does?.routines).items
                let triggers = BotSetWire.items(does?.triggers).items
                let peers = BotSetWire.items(does?.peers).items
                BotsSection(title: "What it does") {
                    line("\(count(routines.count, "routine", "routines")), \(count(triggers.count, "trigger", "triggers")), \(count(does?.openCards ?? 0, "open task", "open tasks")).")
                    if !peers.isEmpty {
                        RowLine()
                        line("It works with " + peers.joined(separator: ", ") + ".")
                    }
                }
                BotsSection(title: "What it can reach") {
                    line(reachLine(overview.reaches))
                }
                let wont = BotSetWire.items(overview.wont).items
                if !wont.isEmpty {
                    BotsSection(title: "What it will not do") {
                        ForEach(Array(wont.enumerated()), id: \.offset) { index, text in
                            if index > 0 { RowLine() }
                            line(text)
                        }
                    }
                }
                let recent = BotSetWire.items(overview.recent).items
                BotsSection(title: "Recent runs") {
                    if recent.isEmpty {
                        EmptyNote(text: "It has not run yet.", symbol: "clock")
                    }
                    ForEach(Array(recent.enumerated()), id: \.offset) { index, run in
                        if index > 0 { RowLine() }
                        HStack {
                            Text(run.name?.isEmpty == false ? run.name ?? "A run" : "A run")
                                .font(KFont.ui(15.5)).foregroundStyle(Palette.ink).lineLimit(1)
                            Spacer()
                            Text(runLine(run))
                                .font(KFont.ui(13.5)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                    }
                }
            }
        }
        .task(id: BotsSettingsLive.connectionKey) {
            await live.loadOverview(botID)
        }
    }

    private func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

    private func whoLine(_ who: BotSetOverviewWhoDTO?, fallback: String) -> String {
        let name = who?.name?.isEmpty == false ? who?.name ?? fallback : fallback
        let role = (who?.role ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let intro = (who?.blurb ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var out = role.isEmpty ? name + "." : "\(name), \(role.prefix(1).lowercased() + role.dropFirst())."
        if !intro.isEmpty { out += " " + intro }
        return out
    }

    private func runLine(_ run: BotSetOverviewRunDTO) -> String {
        let parts = [run.outcome?.capitalized ?? "", BotSetWords.when(run.ranAt?.date)]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func reachLine(_ reach: BotSetOverviewReachDTO?) -> String {
        var parts: [String] = []
        if let apps = reach?.integrations {
            if apps.string == "all" {
                parts.append("It can use every connected app.")
            } else {
                let n = apps.array?.count ?? 0
                parts.append(n == 0 ? "It cannot reach any apps." : "It can use \(count(n, "connected app", "connected apps")).")
            }
        }
        switch reach?.place {
        case "computer": parts.append("It works on the computer.")
        case "browser": parts.append("It works in the browser.")
        case "off": parts.append("It does not use the computer or the browser.")
        default: break
        }
        if let channel = reach?.deliverToChannel, !channel.isEmpty { parts.append("It reports to \(channel).") }
        return parts.isEmpty ? "Nothing is set yet." : parts.joined(separator: " ")
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(KFont.ui(15.5))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
    }
}

/// A row inside a card that can be chosen: a title, an optional detail, and a check when it is the one in use.
private struct BotSetChoiceRow: View {
    let title: String
    var detail: String? = nil
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink).lineLimit(2)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(2)
                    }
                }
                Spacer()
                if on {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.goldText)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Settings > Model and effort, on the bot's record. Each choice is sent on its own.
private struct BotSetModelScreen: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared

    /// Connections that offer more than one version (agent_service.py: _check_model).
    private static let versionKinds: Set<String> = ["claude_cli", "codex_cli", "antigravity_cli", "api"]

    var body: some View {
        let agent = live.record(botID)
        let busy = live.busy.contains(botID)
        BotsPage("Model and effort", subtitle: BotSettingsList.liveModelLine(agent), live: true) {
            BotSetUnsureNote(botID: botID)
            BotsLoadNote(state: live.shown(live.recordLoad[botID])) { Task { await live.loadModel(botID) } }
            if let agent {
                let choice = live.choices.first { $0.id == agent.endpointId }
                BotsSection(title: "Connection") {
                    BotSetChoiceRow(title: "Kairos default", detail: "The first Claude connection on your desktop.", on: agent.endpointId == nil) {
                        guard agent.endpointId != nil else { return }
                        send(["endpoint_id": NSNull()], on: agent, what: "the connection", done: "It uses the default connection now.")
                    }
                    ForEach(live.choices) { option in
                        RowLine()
                        BotSetChoiceRow(title: name(option), detail: option.model, on: option.id == agent.endpointId) {
                            guard option.id != agent.endpointId else { return }
                            send(["endpoint_id": option.id], on: agent, what: "the connection", done: "It uses \(name(option)) now.")
                        }
                    }
                }
                .disabled(busy)
                if case .failed(let text) = live.choicesLoad {
                    BotsLoadNote(state: .failed(text)) { Task { await live.loadChoices() } }
                }

                if let choice, Self.versionKinds.contains(choice.kind ?? ""), let endpoint = agent.endpointId {
                    versions(agent, choice: choice, catalog: live.catalogs[endpoint] ?? [], busy: busy)
                } else if choice != nil {
                    HintLine(text: "This connection runs one model, so there is nothing more to choose.", symbol: "info.circle")
                        .padding(.horizontal, 4)
                }

                effort(agent, choice: choice, busy: busy)

                BotsSection(title: "When it is busy") {
                    MenuRow(title: "Keep warm", options: BotSetWords.keepWarm.map(\.title), selection: Binding(
                        get: { BotSetWords.keepWarm.first { $0.id == (agent.cacheKeepWarm ?? "follow") }?.title ?? "Follow default" },
                        set: { title in
                            guard let id = BotSetWords.keepWarm.first(where: { $0.title == title })?.id,
                                  id != (agent.cacheKeepWarm ?? "follow") else { return }
                            send(["cache_keep_warm": id], on: agent, what: "keep warm", done: "Keep warm is \(title.lowercased()).")
                        }
                    ))
                }
                .disabled(busy)

                fallbacks(agent, busy: busy)

                let others = live.otherModel[botID] ?? 0
                if others > 0 {
                    let switching = live.following.contains(botID)
                    HStack(spacing: 10) {
                        Text(others == 1 ? "1 conversation uses a different model." : "\(others) conversations use a different model.")
                            .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        Spacer()
                        PillButton(title: "Switch them too") {
                            Haptics.tap()
                            Task {
                                let outcome = await live.followModel(botID)
                                if !outcome.text.isEmpty { store.say(outcome.text) }
                            }
                        }
                        .disabled(switching)
                        .opacity(switching ? 0.5 : 1)
                    }
                    .padding(14)
                    .kCard(radius: 18)
                }
            }
        }
        .task(id: BotsSettingsLive.connectionKey) {
            await live.loadModel(botID)
        }
        .task(id: "\(BotsSettingsLive.connectionKey)|\(live.record(botID)?.endpointId ?? "")") {
            if let endpoint = live.record(botID)?.endpointId, live.catalogs[endpoint] == nil { await live.loadCatalog(endpoint) }
        }
    }

    private func name(_ choice: ModelChoiceDTO) -> String {
        if let name = choice.name, !name.isEmpty { return name }
        return choice.model ?? choice.id
    }

    private func versions(_ agent: AgentDTO, choice: ModelChoiceDTO, catalog: [ModelCatalogEntryDTO], busy: Bool) -> some View {
        let current = agent.modelOverride ?? ""
        return BotsSection(title: "Model") {
            BotSetChoiceRow(title: "Connection default", detail: choice.model, on: current.isEmpty) {
                guard !current.isEmpty else { return }
                send(["model_override": NSNull()], on: agent, what: "the model", done: "It uses the connection's default model now.")
            }
            ForEach(catalog) { entry in
                RowLine()
                BotSetChoiceRow(title: entry.displayName ?? entry.id, detail: entry.description, on: entry.id == current) {
                    guard entry.id != current else { return }
                    send(["model_override": entry.id], on: agent, what: "the model", done: "It uses \(entry.displayName ?? entry.id) now.")
                }
            }
            if !current.isEmpty, !catalog.contains(where: { $0.id == current }) {
                RowLine()
                BotSetChoiceRow(title: current, detail: "Set on your desktop", on: true) {}
            }
        }
        .disabled(busy)
    }

    @ViewBuilder
    private func effort(_ agent: AgentDTO, choice: ModelChoiceDTO?, busy: Bool) -> some View {
        let override = agent.modelOverride ?? ""
        let model = override.isEmpty ? (choice?.model ?? "") : override
        let catalog = agent.endpointId.flatMap { live.catalogs[$0] } ?? []
        let entry = catalog.first { $0.id == model }
        let efforts = (entry?.supportedEfforts ?? []).compactMap(\.effort).filter { !$0.isEmpty }
        let now = (agent.modelEffort ?? "").isEmpty ? "default" : (agent.modelEffort ?? "default")
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Effort").padding(.horizontal, 4)
            if efforts.isEmpty {
                HintLine(text: now == "default" ? "This model has no effort setting here." : "Effort is \(BotSetWords.effort(now)). This model offers no other choice here.", symbol: "info.circle")
                    .padding(.horizontal, 4)
            } else {
                GoldSegmented(items: ["default"] + efforts, selection: Binding(
                    get: { now },
                    set: { value in
                        guard value != now else { return }
                        let sent: Any = value == "default" ? NSNull() as Any : value as Any
                        send(["model_effort": sent], on: agent, what: "the effort",
                             done: value == "default" ? "Effort follows the model's default." : "Effort is \(BotSetWords.effort(value)).")
                    }
                ), title: { $0 == "default" ? "Default" : BotSetWords.effort($0) })
                .disabled(busy)
                Text("Higher effort thinks longer and uses more of your plan.")
                    .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).padding(.horizontal, 6)
            }
        }
    }

    private func fallbacks(_ agent: AgentDTO, busy: Bool) -> some View {
        let list = BotSetWire.fallbacks(agent.fallback)
        let open = live.choices.filter { option in option.id != agent.endpointId && !list.contains { $0.endpointID == option.id } }
        return BotsSection(title: "If this model fails", footer: "It tries these in order, up to five.") {
            if list.isEmpty {
                EmptyNote(text: "No fallback models.", symbol: "arrow.triangle.branch")
            }
            ForEach(Array(list.enumerated()), id: \.offset) { index, item in
                if index > 0 { RowLine() }
                HStack {
                    Text("\(index + 1). \(fallbackName(item))").font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer()
                    Button {
                        Haptics.tap()
                        var next = list
                        next.remove(at: index)
                        send(["fallback": next.map(\.plain)], on: agent, what: "the fallback models", done: "\(fallbackName(item)) is no longer a fallback.")
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 20)).foregroundStyle(Palette.danger)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Remove \(fallbackName(item))")
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
            }
            if list.count < 5, !open.isEmpty {
                RowLine()
                Menu {
                    ForEach(open) { option in
                        Button(name(option)) {
                            send(["fallback": (list + [BotSetFallback(endpointID: option.id)]).map(\.plain)],
                                 on: agent, what: "the fallback models", done: "\(name(option)) is a fallback now.")
                        }
                    }
                } label: {
                    Label("Add a fallback", systemImage: "plus")
                        .font(KFont.ui(16, .medium))
                        .foregroundStyle(Palette.goldText)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .padding(.horizontal, 16)
                }
            }
        }
        .disabled(busy)
    }

    private func fallbackName(_ item: BotSetFallback) -> String {
        let base = live.choices.first { $0.id == item.endpointID }.map { name($0) } ?? "A connection not on this list"
        guard let model = item.modelOverride, !model.isEmpty else { return base }
        return "\(base), \(model)"
    }

    /// One choice, sent with the revision of the record it was made on.
    private func send(_ changes: [String: Any], on agent: AgentDTO, what: String, done: String) {
        Task {
            let outcome = await live.patch(botID, changes, revision: agent.revision ?? 0, what: what, done: done)
            if !outcome.text.isEmpty { store.say(outcome.text) }
            if let endpoint = live.records[botID]?.endpointId, live.catalogs[endpoint] == nil { await live.loadCatalog(endpoint) }
            await live.loadOtherModel(botID)
        }
    }
}

/// Settings > Approval. Only lowering is sent: the desktop refuses a raise from a phone.
private struct BotSetApprovalScreen: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared

    var body: some View {
        let policy = live.isCurrent ? live.policies[botID] : nil
        let agent = live.record(botID)
        let busy = live.busy.contains(botID)
        BotsPage("Approval", subtitle: "Before it acts", live: true) {
            BotSetUnsureNote(botID: botID)
            BotsLoadNote(state: live.shown(live.policyLoad[botID])) { Task { await live.loadApproval(botID) } }
            if let policy {
                if let current = BotsSettingsLive.botLevel(policy) {
                    VStack(spacing: 10) {
                        ForEach(ApprovalLevel.allCases, id: \.self) { level in
                            levelCard(level, current: current, policy: policy, busy: busy)
                        }
                    }
                    HintLine(text: "Lowering a level applies at once. To raise one, or to change one conversation's level, use Kairos on your desktop.", symbol: "info.circle")
                } else {
                    HintLine(text: "This bot uses custom approval rules. Change them in Kairos on your desktop.", symbol: "info.circle")
                        .padding(14)
                        .kCard(radius: 18)
                }
            }

            if let agent {
                outside(agent, busy: busy)
            }

            commands()
        }
        .task(id: BotsSettingsLive.connectionKey) {
            await live.loadRecord(botID)
            await live.loadApproval(botID)
        }
    }

    private func commands() -> some View {
        let list = live.isCurrent ? (live.rules[botID] ?? []) : []
        let state = live.shown(live.rulesLoad[botID])
        return BotsSection(title: "Always allowed", footer: "Commands you chose \"Always allow\" for. Remove one to be asked again.") {
            if case .failed(let text) = state {
                BotsLoadNote(state: .failed(text)) { Task { await live.loadRules(botID) } }
                    .padding(8)
            } else if list.isEmpty {
                EmptyNote(text: state == .loaded ? "Nothing is always allowed." : "Reading your desktop.", symbol: "checkmark.shield")
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, rule in
                if index > 0 { RowLine() }
                let removing = live.removing.contains(rule.id)
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rule.command ?? "").font(.system(size: 15, design: .monospaced)).foregroundStyle(Palette.ink).lineLimit(3)
                        if let folder = rule.cwd, !folder.isEmpty {
                            Text("In \(folder)").font(KFont.ui(12.5, relativeTo: .caption)).foregroundStyle(Palette.inkFaint)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer()
                    PillButton(title: "Remove", look: .danger) {
                        Haptics.tap()
                        Task {
                            let outcome = await live.removeRule(botID, rule)
                            if !outcome.text.isEmpty { store.say(outcome.text) }
                        }
                    }
                    .disabled(removing)
                    .opacity(removing ? 0.5 : 1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
    }

    private func outside(_ agent: AgentDTO, busy: Bool) -> some View {
        let policy = BotSetWire.outboundPolicy(agent.outbound)
        let usage = live.outbound[botID]
        return BotsSection(title: "Messages outside the app", footer: "Ringing, calling, messaging or texting you never asks.") {
            GoldSegmented(items: ["Ask", "Allow"], selection: Binding(
                get: { policy == "allow" ? "Allow" : "Ask" },
                set: { value in
                    guard value == "Ask", policy == "allow" else { return }
                    Task {
                        let outcome = await live.patch(botID, ["outbound": ["policy": "ask"]], revision: agent.revision ?? 0,
                                                       what: "the outside-message setting",
                                                       done: "It asks before each outside message.")
                        if !outcome.text.isEmpty { store.say(outcome.text) }
                        await live.loadOutbound(botID)
                    }
                }
            ), title: { $0 }, disabled: { $0 == "Allow" && policy != "allow" })
            .padding(8)
            .disabled(busy)
            RowLine()
            VStack(alignment: .leading, spacing: 6) {
                if policy == "allow", let usage, let cap = usage.cap {
                    let used = usage.used ?? 0
                    Text("\(used) of \(cap) used today. \(usage.remaining ?? max(0, cap - used)) left.")
                        .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                    MeterBar(fraction: Double(used) / Double(max(1, cap)))
                } else {
                    Text("It asks before each outside message. Letting it send them on its own is turned on in Kairos on your desktop.")
                        .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private func levelCard(_ level: ApprovalLevel, current: ApprovalLevel, policy: BotApprovalPolicyDTO, busy: Bool) -> some View {
        let on = level == current
        let higher = level.rank > current.rank
        let info = policy.levels?.first { $0.mode == level.rawValue }
        let unavailable = info?.available == false && !on
        let note: String? = higher ? "Raise it in Kairos on your desktop" : (unavailable ? (info?.reason ?? "Not available on this bot's AI") : nil)
        return Button {
            guard !on, !higher, !unavailable else { return }
            Haptics.select()
            Task {
                let outcome = await live.lower(botID, to: level, revision: policy.revision)
                if !outcome.text.isEmpty { store.say(outcome.text) }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: level.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(on ? Palette.onGold : (higher ? Palette.inkFaint : Palette.goldText))
                    .frame(width: 40, height: 40)
                    .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title).font(KFont.ui(17, .semibold)).foregroundStyle(higher ? Palette.inkDim : Palette.ink)
                    Text(level.hint).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        .multilineTextAlignment(.leading)
                    if let note {
                        Label(note, systemImage: higher ? "desktopcomputer" : "info.circle")
                            .font(KFont.ui(13, .medium, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Palette.goldText : Palette.inkFaint)
                    .opacity(higher ? 0.4 : 1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Palette.surfaceRaised : Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(on ? Palette.gold : Palette.line, lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .disabled(busy || higher || on || unavailable)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Settings > Voice and calls, on the bot's record. Live voice, typed replies and idle end are the account's.
private struct BotSetVoiceScreen: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared

    var body: some View {
        let agent = live.record(botID)
        let busy = live.busy.contains(botID)
        BotsPage("Voice and calls", live: true) {
            BotSetUnsureNote(botID: botID)
            BotsLoadNote(state: live.shown(live.recordLoad[botID])) { Task { await live.loadRecord(botID) } }
            if let agent {
                voice(agent, busy: busy)
                calls(agent, busy: busy)
                if live.liveVoice != nil {
                    HintLine(text: "Live voice, typed replies and idle end apply to every bot. Change them in Kairos on your desktop.", symbol: "info.circle")
                        .padding(.horizontal, 4)
                }
                BotsSection(title: "Alerts") {
                    ToggleRow(title: "Tell me when it needs me", detail: "A notification when it waits for an answer or an OK.", symbol: "bell.badge", isOn: Binding(
                        get: { agent.notifications != false },
                        set: { on in send(["notifications": on], on: agent, what: "alerts", done: on ? "It tells you when it needs you." : "It no longer sends alerts.") }
                    ))
                }
                .disabled(busy)
            }
        }
        .task(id: BotsSettingsLive.connectionKey) {
            await live.loadRecord(botID)
            await live.loadVoices()
        }
    }

    private func voice(_ agent: AgentDTO, busy: Bool) -> some View {
        let options = voiceOptions(agent)
        return BotsSection(title: "Voice", footer: live.voicesNote) {
            MenuRow(title: "Voice", symbol: "waveform", options: options.map(\.title), selection: Binding(
                get: { options.first { $0.id == (agent.voiceId ?? "") }?.title ?? "Default voice" },
                set: { title in
                    guard let id = options.first(where: { $0.title == title })?.id, id != (agent.voiceId ?? "") else { return }
                    let sent: Any = id.isEmpty ? NSNull() as Any : id as Any
                    send(["voice_id": sent], on: agent, what: "the voice", done: "It speaks with \(title) now.")
                }
            ))
            RowLine(inset: 54)
            ToggleRow(title: "Speak its replies", detail: "It reads each reply aloud in its voice.", symbol: "text.bubble", isOn: Binding(
                get: { agent.speakReplies == true },
                set: { on in send(["speak_replies": on], on: agent, what: "speaking replies", done: on ? "It speaks its replies." : "It no longer speaks its replies.") }
            ))
        }
        .disabled(busy)
    }

    private func calls(_ agent: AgentDTO, busy: Bool) -> some View {
        BotsSection(title: "Calls") {
            MenuRow(title: "Call mode", symbol: "phone", options: BotSetWords.callModes.map(\.title), selection: Binding(
                get: { BotSetWords.callModes.first { $0.id == (agent.callMode ?? "turns") }?.title ?? "Same as Settings" },
                set: { title in
                    guard let id = BotSetWords.callModes.first(where: { $0.title == title })?.id, id != (agent.callMode ?? "turns") else { return }
                    send(["call_mode": id], on: agent, what: "the call mode", done: "Call mode is \(title.lowercased()).")
                }
            ))
            .disabled(busy)
            if let settings = live.liveVoice {
                RowLine(inset: 54)
                infoRow("Live voice", "person.wave.2", (settings.voice ?? "marin").capitalized)
                RowLine(inset: 54)
                infoRow("Read typed replies", "keyboard", settings.readTyped == true ? "On" : "Off")
                RowLine(inset: 54)
                infoRow("End an idle call after", "timer", "\(settings.idleMinutes ?? 5) min")
            }
        }
    }

    /// "Default voice" first, then the engine's voices with their names made unique, then the bot's own voice
    /// when the engine does not list it.
    private func voiceOptions(_ agent: AgentDTO) -> [(id: String, title: String)] {
        var out: [(id: String, title: String)] = [("", "Default voice")]
        var used: Set<String> = ["Default voice"]
        for voice in live.voices {
            var title = (voice.name ?? "").isEmpty ? voice.id : (voice.name ?? voice.id)
            if used.contains(title) { title += " (\(voice.id))" }
            guard !used.contains(title) else { continue }
            used.insert(title)
            out.append((voice.id, title))
        }
        if let own = agent.voiceId, !own.isEmpty, !out.contains(where: { $0.id == own }), !used.contains(own) {
            out.append((own, own))
        }
        return out
    }

    private func infoRow(_ title: String, _ symbol: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.goldText).frame(width: 26)
            Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            Text(value).font(KFont.ui(15)).foregroundStyle(Palette.inkDim).lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    /// One choice, sent with the revision of the record it was made on.
    private func send(_ changes: [String: Any], on agent: AgentDTO, what: String, done: String) {
        Task {
            let outcome = await live.patch(botID, changes, revision: agent.revision ?? 0, what: what, done: done)
            if !outcome.text.isEmpty { store.say(outcome.text) }
        }
    }
}

/// Settings > Where it reports: `deliver_to_channel` on the bot, from the desktop's channels.
private struct BotSetDeliveryScreen: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared

    var body: some View {
        let agent = live.record(botID)
        let busy = live.busy.contains(botID)
        BotsPage("Where it reports", live: true) {
            BotSetUnsureNote(botID: botID)
            BotsLoadNote(state: live.shown(live.recordLoad[botID])) { Task { await live.loadRecord(botID) } }
            if let agent {
                reportTo(agent, busy: busy)
                BotsLoadNote(state: live.shown(live.channelsLoad)) { Task { await live.loadChannels() } }
                if !live.channels.isEmpty {
                    channelList()
                    HintLine(text: "Connect a channel in Kairos on your desktop.", symbol: "info.circle")
                        .padding(.horizontal, 4)
                }
            }
        }
        .task(id: BotsSettingsLive.connectionKey) {
            await live.loadRecord(botID)
            await live.loadChannels()
        }
    }

    private func reportTo(_ agent: AgentDTO, busy: Bool) -> some View {
        let options = channelOptions(agent)
        return BotsSection(footer: "Where its reports and questions reach you.") {
            MenuRow(title: "Report to", symbol: "paperplane", options: options.map(\.title), selection: Binding(
                get: { options.first { $0.id == (agent.deliverToChannel ?? "") }?.title ?? "In the app only" },
                set: { title in
                    guard let id = options.first(where: { $0.title == title })?.id, id != (agent.deliverToChannel ?? "") else { return }
                    let sent: Any = id.isEmpty ? NSNull() as Any : id as Any
                    Task {
                        let outcome = await live.patch(botID, ["deliver_to_channel": sent], revision: agent.revision ?? 0,
                                                       what: "where it reports",
                                                       done: id.isEmpty ? "Reports stay in the app." : "It reports to \(title) now.")
                        if !outcome.text.isEmpty { store.say(outcome.text) }
                    }
                }
            ))
        }
        .disabled(busy)
    }

    private func channelList() -> some View {
        BotsSection(title: "Channels (\(live.channels.filter { $0.configured == true }.count) connected)") {
            ForEach(Array(live.channels.enumerated()), id: \.element.id) { index, channel in
                if index > 0 { RowLine(inset: 54) }
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left").foregroundStyle(Palette.goldText).frame(width: 26)
                    Text(channel.label ?? channel.id).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    Spacer()
                    StateTag(text: channel.configured == true ? "Connected" : "Not connected yet",
                             color: channel.configured == true ? Palette.success : Palette.inkFaint)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            }
        }
    }

    /// "In the app only", the connected channels, and the bot's own when it is not one of them.
    private func channelOptions(_ agent: AgentDTO) -> [(id: String, title: String)] {
        var out: [(id: String, title: String)] = [("", "In the app only")]
        var used: Set<String> = ["In the app only"]
        for channel in live.channels where channel.configured == true || channel.id == agent.deliverToChannel {
            var title = (channel.label ?? "").isEmpty ? channel.id : (channel.label ?? channel.id)
            if used.contains(title) { title += " (\(channel.id))" }
            guard !used.contains(title) else { continue }
            used.insert(title)
            out.append((channel.id, title))
        }
        if let own = agent.deliverToChannel, !own.isEmpty, !out.contains(where: { $0.id == own }), !used.contains(own) {
            out.append((own, own))
        }
        return out
    }
}

/// Settings > Limits: on or off, and runs per day. Turning it off is confirmed first. Runs per day is a small form:
/// it remembers the desktop value and revision it was filled from (BotSetForm), and a read never makes it look changed.
private struct BotSetLimitsScreen: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared
    @State private var confirmOff = false
    /// The revision the screen showed when the person turned the switch off.
    @State private var offRevision = 0
    @State private var runs = 12
    @State private var form: BotSetForm?
    @State private var saving = false

    var body: some View {
        let agent = live.record(botID)
        let busy = live.busy.contains(botID)
        BotsPage("Limits", live: true) {
            BotSetUnsureNote(botID: botID)
            BotsLoadNote(state: live.shown(live.recordLoad[botID])) {
                Task {
                    await live.loadRecord(botID)
                    sync()
                }
            }
            if let agent {
                let on = agent.enabled != false
                BotsSection(footer: on ? nil : "Off, it takes no new work and its routines do not run.") {
                    ToggleRow(title: "This bot is on", symbol: "power", isOn: Binding(
                        get: { on },
                        set: { value in
                            if value {
                                send(["enabled": true], revision: agent.revision ?? 0, what: "turning it on", done: "\(store.bot(botID).name) is on.")
                            } else {
                                offRevision = agent.revision ?? 0
                                confirmOff = true
                            }
                        }
                    ))
                }
                .disabled(busy || saving)
                if let form {
                    runsSection(agent, form: form, busy: busy)
                }
                HintLine(text: "Your desktop has no monthly spend cap for one bot. Usage and plan shows what it spends.", symbol: "info.circle")
                    .padding(.horizontal, 4)
            }
        }
        .sheet(isPresented: $confirmOff) {
            ConfirmSheet(title: "Turn \(store.bot(botID).name) off?", detail: "Its routines stop until you turn it on.", confirm: "Turn off") {
                send(["enabled": false], revision: offRevision, what: "turning it off", done: "\(store.bot(botID).name) is off.")
            }
        }
        .task(id: BotsSettingsLive.connectionKey) {
            sync()
            await live.loadRecord(botID)
            sync()
        }
        .onChange(of: live.record(botID)) { sync() }
        .onChange(of: busy) { sync() }
    }

    private func runsSection(_ agent: AgentDTO, form: BotSetForm, busy: Bool) -> some View {
        let stored = agent.dailyRunCap ?? 12
        let edited = !form.edited(values()).isEmpty
        let today = agent.runsToday ?? 0
        return BotsSection(title: "Runs") {
            StepperRow(title: "Runs per day", value: $runs, range: 1...200)
            if edited {
                RowLine()
                HStack(spacing: 10) {
                    Text(form.clashed.isEmpty ? "Not saved yet." : "Your desktop changed it to \(stored). Not saved yet.")
                        .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    PillButton(title: "Keep \(stored)") {
                        runs = stored
                        sync()
                    }
                    PillButton(title: saving ? "Saving" : "Save", look: .filled) { save() }
                        .disabled(saving)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            RowLine()
            VStack(alignment: .leading, spacing: 6) {
                Text("\(today) of \(stored) daily runs used. \(today >= stored ? "It is done for today." : "\(stored - today) left today.")")
                    .font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                MeterBar(fraction: Double(today) / Double(max(1, stored)))
            }
            .padding(14)
        }
        .disabled(busy || saving)
    }

    private static func values(_ agent: AgentDTO) -> [String: String] {
        ["daily_run_cap": String(agent.dailyRunCap ?? 12)]
    }

    private func values() -> [String: String] {
        ["daily_run_cap": String(runs)]
    }

    /// Fill the form from the desktop, or bring an open one up to the newest read. Waits while a change is on its way.
    private func sync(acknowledge: Bool = false) {
        guard live.isCurrent, let agent = live.record(botID), !saving, !live.busy.contains(botID) else { return }
        let desktop = Self.values(agent)
        let revision = agent.revision ?? 0
        guard var next = form, next.account == BotsSettingsLive.accountKey else {
            runs = agent.dailyRunCap ?? 12
            form = BotSetForm(account: BotsSettingsLive.accountKey, revision: revision, values: desktop)
            return
        }
        for key in next.rebase(form: values(), desktop: desktop, revision: revision, acknowledge: acknowledge)
        where key == "daily_run_cap" {
            runs = agent.dailyRunCap ?? 12
        }
        form = next
    }

    private func save() {
        guard let form, !saving, form.edited(values()).contains("daily_run_cap") else { return }
        let draft = runs
        Haptics.tap()
        saving = true
        Task {
            let outcome = await live.patch(botID, ["daily_run_cap": draft], revision: form.revision,
                                           what: "runs per day", done: "It runs up to \(draft) times a day.")
            saving = false
            if case .changed = outcome {
                sync(acknowledge: true)
                store.say("This bot changed on your desktop, so runs per day was not saved. Your number is kept here; save again to use it.")
            } else {
                sync()
                if !outcome.text.isEmpty { store.say(outcome.text) }
            }
        }
    }

    /// One switch, sent with the revision of the record it was made on.
    private func send(_ changes: [String: Any], revision: Int, what: String, done: String) {
        Task {
            let outcome = await live.patch(botID, changes, revision: revision, what: what, done: done)
            if !outcome.text.isEmpty { store.say(outcome.text) }
        }
    }
}

/// Settings > Standing instructions. A form over the bot record (BotSetForm): it remembers the desktop text and
/// revision it was filled from, sends only what the person edited with that revision, and never saves over a hand
/// edit of the instructions file.
private struct BotSetInstructionsScreen: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared
    @State private var text = ""
    @State private var intro = ""
    @State private var style = "Default"
    @State private var form: BotSetForm?
    @State private var saving = false

    private static let soulLimit = 24_000
    private static let introLimit = 4_000

    var body: some View {
        let agent = live.record(botID)
        let soul = live.isCurrent ? live.souls[botID] : nil
        let handEdited = soul?.inSync == false
        let edited = form?.edited(values()) ?? []
        let tooLong = text.utf8.count > (soul?.limit ?? Self.soulLimit) || BotSetForm.length(intro) > Self.introLimit
        BotsPage("Standing instructions", live: true) {
            BotSetUnsureNote(botID: botID)
            BotsLoadNote(state: live.shown(soul == nil ? live.soulLoad[botID] : live.recordLoad[botID])) {
                Task {
                    await live.loadRecord(botID)
                    await live.loadSoul(botID)
                    sync()
                }
            }
            if let form, agent != nil, soul != nil {
                if handEdited {
                    HintLine(text: "The instructions file was edited by hand on your desktop, so nothing here can be saved. Keep or discard that edit in Kairos on your desktop first.", symbol: "exclamationmark.triangle", color: Palette.goldText)
                        .padding(14)
                        .kCard(radius: 18)
                }
                FieldCard(title: "Standing instructions", text: $text, placeholder: "How it should work, always", limit: Self.soulLimit, lines: 6...14)
                FieldCard(title: "Introduction", text: $intro, placeholder: "A short line about who it is.", limit: Self.introLimit, lines: 2...5)
                BotsSection(title: "Reply style") {
                    GoldSegmented(items: ["Default", "Conversational"], selection: $style) { $0 }.padding(8)
                }
                let clashed = form.clashed.intersection(edited)
                if !clashed.isEmpty {
                    HintLine(text: "Your desktop changed \(Self.list(clashed)) while you were editing. Your text is kept here; saving puts it in place of your desktop's.", symbol: "exclamationmark.triangle", color: Palette.goldText)
                }
                GoldButton(title: saving ? "Saving" : "Save instructions") { save() }
                    .disabled(edited.isEmpty || saving || handEdited || tooLong || live.busy.contains(botID))
                if tooLong {
                    HintLine(text: "This is longer than your desktop keeps. Shorten it to save.", symbol: "exclamationmark.circle", color: Palette.danger)
                } else if !edited.isEmpty && !saving {
                    HintLine(text: "Changes are not saved yet.", symbol: "circle.dotted")
                }
                NavigationLink(value: BotsRoute.settings(botID, .history)) {
                    Text("See how this changed").font(KFont.ui(15, .medium)).foregroundStyle(Palette.goldText).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        // Read each time the page appears (coming back from History too) and when the connection becomes ready.
        .task(id: BotsSettingsLive.connectionKey) {
            sync()
            await live.loadRecord(botID)
            await live.loadSoul(botID)
            sync()
        }
        .onChange(of: live.record(botID)) { sync() }
        .onChange(of: live.busy.contains(botID)) { sync() }
    }

    private static func list(_ fields: Set<String>) -> String {
        let order = ["soul", "blurb", "reply_style"]
        let words = order.filter { fields.contains($0) }.map { BotSetWords.field($0) }
        return words.count > 1 ? words.dropLast().joined(separator: ", ") + " and " + (words.last ?? "") : (words.first ?? "")
    }

    /// The desktop's values, from one record read (text and revision together).
    private static func values(_ agent: AgentDTO) -> [String: String] {
        ["soul": agent.soul ?? "", "blurb": agent.blurb ?? "",
         "reply_style": agent.replyStyle == "conversational" ? "conversational" : "default"]
    }

    private func values() -> [String: String] {
        ["soul": text, "blurb": intro, "reply_style": style == "Conversational" ? "conversational" : "default"]
    }

    private func refill(_ key: String, from agent: AgentDTO) {
        switch key {
        case "soul": text = agent.soul ?? ""
        case "blurb": intro = agent.blurb ?? ""
        case "reply_style": style = agent.replyStyle == "conversational" ? "Conversational" : "Default"
        default: break
        }
    }

    /// Fill the form from the desktop, or bring an open one up to the newest read: untouched fields take the
    /// desktop's values, edited ones stay. Waits while a change is on its way.
    private func sync(acknowledge: Bool = false) {
        guard live.isCurrent, let agent = live.record(botID), !saving, !live.busy.contains(botID) else { return }
        let desktop = Self.values(agent)
        let revision = agent.revision ?? 0
        guard var next = form, next.account == BotsSettingsLive.accountKey else {
            for key in desktop.keys { refill(key, from: agent) }
            form = BotSetForm(account: BotsSettingsLive.accountKey, revision: revision, values: desktop)
            return
        }
        for key in next.rebase(form: values(), desktop: desktop, revision: revision, acknowledge: acknowledge) {
            refill(key, from: agent)
        }
        form = next
    }

    private func save() {
        guard let form, !saving else { return }
        let now = values()
        let edited = form.edited(now)
        guard !edited.isEmpty else { return }
        var changes: [String: Any] = [:]
        for key in edited { changes[key] = now[key] }
        saving = true
        Task {
            let outcome = await live.patch(botID, changes, revision: form.revision, what: "the instructions", done: "Instructions saved.")
            await live.loadSoul(botID)
            saving = false
            if case .changed = outcome {
                sync(acknowledge: true)
                store.say("They changed on your desktop, so nothing was saved. Your edits are kept here and the rest shows what your desktop has. Save again to use yours.")
            } else {
                sync()
                if !outcome.text.isEmpty { store.say(outcome.text) }
            }
            if outcome.isDone { Haptics.success() }
        }
    }
}

/// Settings > History: the desktop's record of changes. Only standing instructions can be put back.
private struct BotSetHistoryScreen: View {
    let botID: String
    let store = BotsStore.shared
    var live = BotsSettingsLive.shared
    @State private var undoing: BotSetHistoryRowDTO?

    var body: some View {
        let history = live.isCurrent ? live.histories[botID] : nil
        let rows = BotSetWire.items(history?.rows).items
        let busy = live.busy.contains(botID)
        BotsPage("History", subtitle: history?.revision.map { "Settings version \($0)" }, live: true) {
            BotSetUnsureNote(botID: botID)
            BotsLoadNote(state: live.shown(live.historyLoad[botID])) { Task { await live.loadHistory(botID) } }
            if history != nil {
                if rows.isEmpty {
                    EmptyNote(text: "Nothing has changed since history started.", symbol: "clock").kCard(radius: 20)
                } else {
                    BotsSection(title: "Changes") {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { RowLine() }
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(BotSetWords.actor(row.actor)) changed \(BotSetWords.field(row.field))")
                                        .font(KFont.ui(15.5)).foregroundStyle(Palette.ink)
                                    Text(BotSetWords.when(row.ts.map { Date(timeIntervalSince1970: $0) }))
                                        .font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer()
                                if row.field == "soul" {
                                    PillButton(title: "Undo") {
                                        Haptics.tap()
                                        undoing = row
                                    }
                                    .disabled(busy)
                                    .opacity(busy ? 0.5 : 1)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(minHeight: 52)
                        }
                    }
                    HintLine(text: "Only standing instructions can be put back from here.", symbol: "info.circle")
                        .padding(.horizontal, 4)
                }
            }
        }
        .sheet(item: $undoing) { row in
            ConfirmSheet(title: "Put the earlier instructions back?",
                         detail: "The standing instructions go back to how they were before this change. History keeps both.",
                         confirm: "Put them back", danger: false) {
                Task {
                    let outcome = await live.rollback(botID, row)
                    if !outcome.text.isEmpty { store.say(outcome.text) }
                }
            }
        }
        .task(id: BotsSettingsLive.connectionKey) {
            await live.loadHistory(botID)
        }
    }
}
