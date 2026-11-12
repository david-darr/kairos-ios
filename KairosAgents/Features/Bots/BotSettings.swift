import SwiftUI

/// The Settings half of a bot's panel: every part of the bot, as rows that open pages.
struct BotSettingsList: View {
    let botID: String
    let store = BotsStore.shared

    var body: some View {
        let bot = store.bot(botID)
        let s = store.settings(botID)
        let routines = store.routines(for: botID)
        let triggers = store.triggers.filter { $0.botID == botID }
        VStack(alignment: .leading, spacing: 18) {
            if store.liveMode {
                liveGlance(bot)
                HintLine(text: "The settings below are not connected to your desktop yet. They show sample data.", symbol: "info.circle")
                    .padding(.horizontal, 4)
            } else {
                glance(bot, s)
            }

            group("How it thinks", [
                row(.model, "Model and effort", "cpu", value: "\(s.model) · \(s.effort.title)"),
                row(.approval, "Approval", "checkmark.shield", value: s.approval.title),
                row(.limits, "Limits", "gauge.with.dots.needle.33percent", value: s.botOn ? "\(s.runsPerDay) runs a day" : "Off"),
            ])

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "What it does on its own").padding(.horizontal, 4)
                VStack(spacing: 0) {
                    NavigationLink(value: BotsRoute.routines(botID)) {
                        NavRow(title: "Routines and triggers", symbol: "clock.arrow.circlepath", value: "\(routines.count + triggers.count)")
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
                row(.voice, "Voice and calls", "waveform", value: s.voice),
                row(.delivery, "Where it reports", "paperplane", value: s.reportTo),
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

    var body: some View {
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

    var body: some View {
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

    var body: some View {
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

    var body: some View {
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

    var body: some View {
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

    var body: some View {
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

    var body: some View {
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

    var body: some View {
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
