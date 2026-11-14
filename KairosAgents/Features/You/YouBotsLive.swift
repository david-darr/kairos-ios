import CryptoKit
import SwiftUI

/// Where one desktop read stands, for one plain sentence on screen.
nonisolated enum YouBotsLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// The parts of You > Bots pages and Channels that are read from the paired desktop, each on its own.
nonisolated enum YouBotsPart: Hashable, Sendable {
    case defaults, keys, logins, library, usage, housekeeping, templates, computers, apps, connectors, discord
}

nonisolated struct YouBotsDefaults: Hashable, Sendable {
    var threadLimit: Int?
    var dailyRunCap: Int?
    var keepSignedIn: Bool?
    var memoryUpkeep: Bool?
    var place: String?
}

/// One key slot as a yes or no. The key, its last four characters and any saved value never reach the phone.
nonisolated struct YouBotsKeyRow: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    var hint: String
    var group: String
    var hasValue: Bool
    var inModels: Bool
}

nonisolated struct YouBotsResources: Hashable, Sendable {
    /// "automatic", "off" or "chosen" (the connection itself is not kept).
    var helper: String
    var tidyTime: String?
    var quietMinutes: Int?
    var roomCapture: String?
}

nonisolated struct YouBotsSkillRow: Identifiable, Hashable, Sendable {
    let id: String
    var summary: String
    var origin: String
    var tags: [String]
    var enabled: Bool
    var effective: Bool
    var changed: Bool
    var warning: Bool
    var everyBot: Bool
    /// The desktop's revision of this skill; a switch-off is sent against it.
    var revision: String?
}

nonisolated struct YouBotsSpend: Hashable, Sendable {
    var cap: Double?
    var spent: Double
    var warnPercent: Int
    var month: String?
    var unknown: Bool
    var capped: Bool
    var nearCap: Bool
    var note: String?

    var ratio: Double { (cap ?? 0) > 0 ? spent / (cap ?? 1) : 0 }
}

nonisolated struct YouBotsBotSpend: Identifiable, Hashable, Sendable {
    let id: String
    var cost: Double?
    var runs: Int
}

nonisolated struct YouBotsHousekeeping: Hashable, Sendable {
    var days: Int
    var megabytes: Double
}

/// What the person changed in the housekeeping form since it was filled. Nil is "not touched".
nonisolated struct YouBotsHousekeepingEdits: Hashable, Sendable {
    var days: Int?
    var megabytes: Int?
    /// The desktop's value at the moment the field was first edited. A later read never moves it, so a save can tell
    /// that the desktop changed the same field under the open form.
    var fromDays: Int?
    var fromMegabytes: Int?

    var isEmpty: Bool { days == nil && megabytes == nil }
}

nonisolated struct YouBotsTeam: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var summary: String
    var members: [String]
}

nonisolated struct YouBotsComputer: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var running: Bool
    var takenOver: Bool
}

nonisolated struct YouBotsComputerInfo: Hashable, Sendable {
    var maxRunning: Int?
    var idleMinutes: Int?
    var dockerAvailable: Bool?
    var dockerReason: String
    var imageReady: Bool?
}

nonisolated struct YouBotsAccount: Identifiable, Hashable, Sendable {
    let id: String
    var alias: String
    var status: String
}

nonisolated struct YouBotsApp: Identifiable, Hashable, Sendable {
    let id: String
    var isMCP: Bool
    var name: String
    var category: String
    var summary: String
    /// connected, expired, failed, pending, off, added or unavailable.
    var state: String
    var enabled: Bool
    var usedBy: [String]
    var accounts: [YouBotsAccount]
}

nonisolated struct YouBotsChannel: Identifiable, Hashable, Sendable {
    let id: String
    var kind: String
    var name: String
    var label: String
    var enabled: Bool
    var twoWay: Bool
    var webhook: Bool
    var anyone: Bool
    var senders: Int
    /// listening, connected, starting, error or off.
    var state: String
}

nonisolated struct YouBotsOverride: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    /// normal, open or silent.
    var mode: String
}

nonisolated struct YouBotsDiscord: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var hasToken: Bool
    var hasAllowedUser: Bool
    var hasVoice: Bool
    var overrides: [YouBotsOverride]
}

/// Where one channel test stands. A test sends a real message and has no request id.
nonisolated enum YouBotsTestState: Equatable, Sendable {
    case sending
    case sent
    /// The desktop answered that it did not send it.
    case refused(String)
    /// No answer came: it may have been sent. No second test is offered.
    case unconfirmed
}

/// What a save sent, shared by the closures of one change so a lost answer is judged against it.
private final class YouBotsSentBox {
    var housekeeping: YouBotsHousekeeping?
    var alias = ""
}

private struct YouBotsWords {
    var done: String
    var failed: String
    /// The desktop answered 404: what the change wanted is already true.
    var missingIsDone = false
    /// What a 409 means for this change.
    var conflict = "It changed on your desktop, so nothing was changed. What your desktop has now is shown."
}

/// The paired desktop behind You > Bots pages and Channels. Unpaired, nothing here runs and every screen shows its
/// sample data. Paired, only narrowing changes and a few small reversible ones are sent: turn a skill, an app server
/// or a channel off, set a Discord override to silent or normal, remove an override, clear a Discord voice, put a
/// bot's computer to sleep, name a Google account, change housekeeping, and the first way bots call you. A channel
/// test sends a real message once and is never repeated after a lost answer. No key, password, token, two-step seed,
/// webhook address, topic, server address, command, link, connector setting or account is ever read, sent or kept.
@Observable
final class YouBotsLive {
    static let shared = YouBotsLive()

    private(set) var loads: [YouBotsPart: YouBotsLoad] = [:]
    private(set) var defaults: YouBotsDefaults?
    private(set) var keys: [YouBotsKeyRow] = []
    private(set) var skippedKeys = 0
    private(set) var resources: YouBotsResources?
    private(set) var logins: [BotKnowLoginDTO] = []
    private(set) var skippedLogins = 0
    private(set) var onePassword: BotKnowOnePasswordDTO?
    private(set) var skills: [YouBotsSkillRow] = []
    private(set) var skippedSkills = 0
    private(set) var pendingShares = 0
    private(set) var spend: YouBotsSpend?
    private(set) var botSpend: [YouBotsBotSpend] = []
    private(set) var skippedBotSpend = 0
    /// The housekeeping form as the desktop has it, and what the person changed on top.
    private(set) var housekeepingFilled: YouBotsHousekeeping?
    private(set) var housekeepingEdits = YouBotsHousekeepingEdits()
    private(set) var teams: [YouBotsTeam] = []
    private(set) var skippedTeams = 0
    private(set) var computers: [YouBotsComputer] = []
    private(set) var skippedComputers = 0
    private(set) var computerInfo: YouBotsComputerInfo?
    private(set) var apps: [YouBotsApp] = []
    private(set) var skippedApps = 0
    private(set) var botsWithoutApps: [String] = []
    /// Alias text the person typed and has not saved, by "app|account". An alias that equals the desktop's is no edit.
    private(set) var aliasEdits: [String: String] = [:]
    private(set) var channels: [YouBotsChannel] = []
    private(set) var skippedChannels = 0
    private(set) var discordBots: [YouBotsDiscord] = []
    private(set) var skippedDiscord = 0
    /// Names of the Discord bots the desktop says are connected now; nil when that could not be read.
    private(set) var discordLive: Set<String>?
    private(set) var checkedAt: Date?
    /// Channel tests, by account and channel. They are NOT dropped when the connection changes: a test whose answer
    /// was lost must stay off after leaving the screen, reopening it or unpairing (and, through `markKey`, after the app
    /// is closed and opened again).
    private(set) var tests: [String: YouBotsTestState] = [:]
    /// The first-call change is moving a way up Reach me's call order.
    private(set) var callChanging = false
    /// Changes on their way: "skill:<name>", "connector:<id>", "mcp:<id>", "sleep:<bot>", "alias:<app>|<account>",
    /// "override:<entry>", "voice:<bot>", "housekeeping".
    private(set) var busy: Set<String> = []
    /// Changes the desktop did not confirm and that could not be checked. No second tap until a read shows them.
    private(set) var unconfirmed: [YouBotsPart: Set<String>] = [:]
    /// One plain sentence per part after a change that did not go through.
    var notice: [YouBotsPart: String] = [:]
    /// Parts the desktop refused for this account (403): the screen shows one plain line.
    private(set) var memberOnly: Set<YouBotsPart> = []

    @ObservationIgnored private var liveAccount = "sample"
    @ObservationIgnored private var reads: [YouBotsPart: Int] = [:]
    @ObservationIgnored private var writes: [YouBotsPart: Int] = [:]
    @ObservationIgnored private var writing: [YouBotsPart: Int] = [:]

    private init() {}

    // MARK: The connection

    static var connectionKey: String { YouAccessLive.connectionKey }
    static var accountKey: String { YouAccessLive.accountKey }
    /// Paired: the screens show only what the desktop sends.
    static var isPaired: Bool { YouAccessLive.isPaired }
    static var isAdmin: Bool { YouAccessLive.isAdmin }

    private var isLive: Bool { Self.isPaired }

    private func stillLive(_ account: String) -> Bool {
        isLive && liveAccount == account && Self.accountKey == account
    }

    /// Drop everything read from another desktop or account. Channel tests stay (see `tests`).
    func followConnection() {
        let key = Self.accountKey
        guard key != liveAccount else { return }
        loads = [:]
        defaults = nil
        keys = []
        skippedKeys = 0
        resources = nil
        logins = []
        skippedLogins = 0
        onePassword = nil
        skills = []
        skippedSkills = 0
        pendingShares = 0
        spend = nil
        botSpend = []
        skippedBotSpend = 0
        housekeepingFilled = nil
        housekeepingEdits = YouBotsHousekeepingEdits()
        teams = []
        skippedTeams = 0
        computers = []
        skippedComputers = 0
        computerInfo = nil
        apps = []
        skippedApps = 0
        botsWithoutApps = []
        aliasEdits = [:]
        channels = []
        skippedChannels = 0
        discordBots = []
        skippedDiscord = 0
        discordLive = nil
        checkedAt = nil
        callChanging = false
        busy = []
        unconfirmed = [:]
        notice = [:]
        memberOnly = []
        reads = [:]
        writes = [:]
        writing = [:]
        liveAccount = key
    }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    func load(_ part: YouBotsPart) -> YouBotsLoad? { loads[part] }

    private func ensureLive(_ account: String) throws {
        guard stillLive(account) else { throw YouBotsNotSent(plain: "Your paired desktop changed. Try again.") }
    }

    // MARK: Reading

    func read(_ part: YouBotsPart) async {
        followConnection()
        guard isLive else { return }
        switch part {
        case .defaults:
            await read(part, "The new bot defaults could not be read.", fetch: { try await $0.youBotsDefaults() }) { dto in
                self.defaults = Self.defaultsState(dto)
            }
        case .keys:
            await read(part, "Your keys could not be read.", fetch: { client -> (YouBotsKeysDTO, YouBotsResourceDTO) in
                (try await client.youBotsKeys(), try await client.youBotsResources())
            }) { pair in
                let shaped = Self.keyRows(pair.0)
                self.keys = shaped.rows
                self.skippedKeys = shaped.skipped
                self.resources = Self.resourcesState(pair.1)
            }
        case .logins:
            await read(part, "Your saved logins could not be read.", fetch: { try await $0.botKnowledgeLogins() }) { dto in
                let found = BotKnowWire.items(dto.logins)
                self.logins = found.items
                self.skippedLogins = found.skipped
                self.onePassword = dto.onepassword
            }
        case .library:
            await read(part, "The skill library could not be read.", fetch: { try await $0.youBotsLibrary() }) { dto in
                let shaped = Self.skillRows(dto)
                self.skills = shaped.rows
                self.skippedSkills = shaped.skipped
                self.pendingShares = dto.pendingShares?.count ?? 0
            }
        case .usage:
            await read(part, "Your usage could not be read.", fetch: { client -> (YouBotsBudgetDTO, BotKnowUsageSummaryDTO) in
                let now = Date()
                return (try await client.youBotsBudget(), try await client.youBotsUsageByBot(from: YouBotsWire.monthStart(now), to: now))
            }) { pair in
                self.spend = Self.spendState(pair.0)
                let shaped = Self.botSpendRows(pair.1)
                self.botSpend = shaped.rows
                self.skippedBotSpend = shaped.skipped
            }
        case .housekeeping:
            await read(part, "Housekeeping could not be read.", fetch: { try await $0.youBotsHousekeeping() }) { dto in
                self.showHousekeeping(Self.housekeepingState(dto))
            }
        case .templates:
            await read(part, "The ready-made teams could not be read.", fetch: { try await $0.youBotsTemplates() }) { dto in
                let shaped = Self.teamRows(dto)
                self.teams = shaped.rows
                self.skippedTeams = shaped.skipped
            }
        case .computers:
            await read(part, "The bot computers could not be read.", fetch: { try await $0.youBotsComputers() }) { dto in
                let shaped = Self.computerRows(dto)
                self.computers = shaped.rows
                self.skippedComputers = shaped.skipped
                self.computerInfo = Self.computerState(dto)
            }
        case .apps:
            await read(part, "Your connected apps could not be read.", fetch: { try await $0.youBotsApps() }) { dto in
                let shaped = Self.appRows(dto)
                self.showApps(shaped.rows)
                self.skippedApps = shaped.skipped
                self.botsWithoutApps = shaped.without
            }
        case .connectors:
            await read(part, "Your channels could not be read.", fetch: { try await $0.youBotsConnectors() }) { list in
                let shaped = Self.channelRows(list)
                self.channels = shaped.rows
                self.skippedChannels = shaped.skipped
                self.checkedAt = Date()
            }
        case .discord:
            await read(part, "Your Discord bots could not be read.", fetch: { client -> ([BotKnowLossy<YouBotsDiscordDTO>], Set<String>?) in
                let list = try await client.youBotsDiscordBots()
                // Whether each one is connected right now is a nice extra: its failure never hides the list.
                let status = try? await client.youBotsStatus()
                let names = status?.discordConnectedBots.map { Set($0.compactMap { $0.string }) }
                return (list, names)
            }) { pair in
                let shaped = Self.discordRows(pair.0)
                self.discordBots = shaped.rows
                self.skippedDiscord = shaped.skipped
                self.discordLive = pair.1
                self.checkedAt = Date()
            }
        }
    }

    @discardableResult
    private func read<T>(_ part: YouBotsPart, _ failure: String, fetch: (APIClient) async throws -> T,
                         apply: (T) -> Void) async -> Bool {
        let account = liveAccount
        let mine = (reads[part] ?? 0) + 1
        reads[part] = mine
        if loads[part] != .loaded { loads[part] = .loading }
        for _ in 0..<3 {
            let before = writes[part] ?? 0
            do {
                let value = try await fetch(try liveClient())
                guard stillLive(account), mine == reads[part] else { return false }
                // A read never overwrites a change on its way: that change reads again when it ends.
                guard (writing[part] ?? 0) == 0 else { return false }
                guard before == (writes[part] ?? 0) else { continue }
                memberOnly.remove(part)
                apply(value)
                if unconfirmed[part]?.isEmpty == false {
                    unconfirmed[part] = nil
                    notice[part] = "Your desktop was checked again. What it has now is shown."
                }
                loads[part] = .loaded
                return true
            } catch {
                if error is CancellationError || Task.isCancelled { return false }
                // An answer for a pairing that has ended never changes the connection.
                guard stillLive(account) else { return false }
                Connection.shared.note(error)
                guard mine == reads[part] else { return false }
                if case .server(status: 403, _)? = error as? APIError {
                    memberOnly.insert(part)
                    loads[part] = .loaded
                    return false
                }
                loads[part] = .failed(failure + " " + YouBotsWire.safe(error.plainWords))
                return false
            }
        }
        guard stillLive(account), mine == reads[part] else { return false }
        if loads[part] != .loaded { loads[part] = .failed(failure + " It kept changing while it was read. Try again.") }
        return false
    }

    // MARK: Shaping (also run by the decode checks)

    nonisolated static func defaultsState(_ dto: YouBotsDefaultsDTO) -> YouBotsDefaults {
        let values = dto.defaults
        return YouBotsDefaults(threadLimit: values?.threadLimit?.int, dailyRunCap: values?.dailyRunCap?.int,
                               keepSignedIn: values?.keepSignedIn?.bool, memoryUpkeep: values?.memoryUpkeep?.bool,
                               place: values?.place?.string)
    }

    nonisolated static func keyRows(_ dto: YouBotsKeysDTO) -> (rows: [YouBotsKeyRow], skipped: Int) {
        let found = BotKnowWire.items(dto.keys)
        var rows: [YouBotsKeyRow] = []
        for slot in found.items {
            let label: String = YouBotsWire.safe(slot.label?.string ?? slot.id)
            let hint: String = YouBotsWire.safe(slot.hint?.string ?? "")
            rows.append(YouBotsKeyRow(id: slot.id, label: label, hint: hint, group: slot.group?.string ?? "Other",
                                      hasValue: slot.hasValue?.bool ?? false, inModels: slot.managedIn?.string == "models"))
        }
        return (rows, found.skipped)
    }

    nonisolated static func resourcesState(_ dto: YouBotsResourceDTO) -> YouBotsResources {
        let helper: String
        if let choice = dto.helperModel?.string, !choice.isEmpty {
            helper = choice == "off" ? "off" : "chosen"
        } else {
            helper = "automatic"
        }
        return YouBotsResources(helper: helper, tidyTime: dto.tidyTime?.string, quietMinutes: dto.captureQuietMinutes?.int,
                                roomCapture: dto.roomCapture?.string)
    }

    nonisolated static func originWords(_ origin: String) -> String {
        switch origin {
        case "private": return "Written for a bot"
        case "library": return "In the library"
        case "global": return "From the Tool Store"
        case "shared": return "Shared by a bot"
        case "imported": return "Imported"
        case "": return "In the library"
        default: return YouBotsWire.safe(String(origin.prefix(30)))
        }
    }

    nonisolated static func skillRows(_ dto: YouBotsLibraryDTO) -> (rows: [YouBotsSkillRow], skipped: Int) {
        let found = BotKnowWire.items(dto.skills)
        var rows: [YouBotsSkillRow] = []
        for skill in found.items where skill.retired?.bool != true {
            var tags: [String] = []
            for tag in skill.tags ?? [] {
                if let text = tag.string { tags.append(YouBotsWire.safe(text)) }
            }
            let summary: String = YouBotsWire.safe(skill.description?.string ?? "")
            let origin: String = originWords(skill.origin?.string ?? "")
            let warning: Bool = (skill.warnings?.count ?? 0) > 0
            rows.append(YouBotsSkillRow(id: skill.name, summary: summary, origin: origin, tags: tags,
                                        enabled: skill.enabled?.bool ?? false, effective: skill.effectiveEnabled?.bool ?? false,
                                        changed: skill.changedAfterReview?.bool ?? false, warning: warning,
                                        everyBot: skill.everyBot?.bool ?? false, revision: skill.storageRevision?.string))
        }
        return (rows, found.skipped)
    }

    nonisolated static func spendState(_ dto: YouBotsBudgetDTO) -> YouBotsSpend? {
        guard let spent = dto.spentUsd?.double else { return nil }
        return YouBotsSpend(cap: dto.monthlyUsd?.double, spent: spent, warnPercent: dto.warnPercent?.int ?? 80, month: dto.month?.string,
                            unknown: dto.spendUnknown?.bool ?? false, capped: dto.capped?.bool ?? false, nearCap: dto.nearCap?.bool ?? false,
                            note: dto.costNote?.string)
    }

    nonisolated static func botSpendRows(_ dto: BotKnowUsageSummaryDTO) -> (rows: [YouBotsBotSpend], skipped: Int) {
        let found = BotKnowWire.items(dto.groups)
        let rows = found.items.compactMap { group -> YouBotsBotSpend? in
            guard let key = group.key, !key.isEmpty else { return nil }
            return YouBotsBotSpend(id: key, cost: group.costUsd, runs: group.runs ?? 0)
        }
        return (rows.sorted { ($0.cost ?? -1) > ($1.cost ?? -1) }, found.skipped)
    }

    nonisolated static func housekeepingState(_ dto: YouBotsHousekeepingDTO) -> YouBotsHousekeeping? {
        guard let days = dto.eventRetentionDays?.int, let megabytes = dto.eventSizeCapMb?.double else { return nil }
        return YouBotsHousekeeping(days: days, megabytes: megabytes)
    }

    nonisolated static func teamRows(_ dto: YouBotsTemplatesDTO) -> (rows: [YouBotsTeam], skipped: Int) {
        let found = BotKnowWire.items(dto.teams)
        var rows: [YouBotsTeam] = []
        for team in found.items {
            var members: [String] = []
            for member in BotKnowWire.items(team.package?.bots).items {
                if let name = member.name?.string { members.append(YouBotsWire.safe(name)) }
            }
            let name: String = YouBotsWire.safe(team.name?.string ?? team.id)
            let summary: String = YouBotsWire.safe(team.description?.string ?? "")
            rows.append(YouBotsTeam(id: team.id, name: name, summary: summary, members: members))
        }
        return (rows, found.skipped)
    }

    nonisolated static func computerRows(_ dto: YouBotsComputersDTO) -> (rows: [YouBotsComputer], skipped: Int) {
        let found = BotKnowWire.items(dto.computers)
        let rows = found.items.map { item in
            YouBotsComputer(id: item.botId, name: YouBotsWire.safe(item.name?.string ?? "A bot"), running: item.running?.bool ?? false,
                            takenOver: item.takenOver?.bool ?? false)
        }
        return (rows, found.skipped)
    }

    nonisolated static func computerState(_ dto: YouBotsComputersDTO) -> YouBotsComputerInfo {
        YouBotsComputerInfo(maxRunning: dto.settings?.maxRunning?.int, idleMinutes: dto.settings?.idleMinutes?.int,
                            dockerAvailable: dto.docker?.available?.bool, dockerReason: YouBotsWire.safe(dto.docker?.reason?.string ?? ""),
                            imageReady: dto.docker?.imageReady?.bool)
    }

    nonisolated static func appRows(_ dto: YouBotsConnectionsDTO) -> (rows: [YouBotsApp], skipped: Int, without: [String]) {
        let found = BotKnowWire.items(dto.apps)
        var rows: [YouBotsApp] = []
        // An app the desktop only lists in its catalogue is not one of the person's apps.
        for app in found.items where app.state?.string != "available" {
            var usedBy: [String] = []
            for user in BotKnowWire.items(app.usedBy).items {
                if let name = user.name?.string { usedBy.append(YouBotsWire.safe(name)) }
            }
            var accounts: [YouBotsAccount] = []
            for account in BotKnowWire.items(app.accounts).items {
                accounts.append(YouBotsAccount(id: account.id, alias: account.alias?.string ?? "", status: account.status?.string ?? ""))
            }
            let name: String = YouBotsWire.safe(app.label?.string ?? app.id)
            let category: String = YouBotsWire.safe(app.category?.string ?? "Apps")
            let summary: String = YouBotsWire.safe(app.description?.string ?? "")
            rows.append(YouBotsApp(id: app.id, isMCP: app.kind?.string == "mcp", name: name, category: category, summary: summary,
                                   state: app.state?.string ?? "unknown", enabled: app.enabled?.bool ?? true,
                                   usedBy: usedBy, accounts: accounts))
        }
        var without: [String] = []
        for bot in BotKnowWire.items(dto.botsWithoutApps).items {
            if let name = bot.name?.string { without.append(YouBotsWire.safe(name)) }
        }
        return (rows, found.skipped, without)
    }

    nonisolated static func channelRows(_ list: [BotKnowLossy<YouBotsConnectorDTO>]) -> (rows: [YouBotsChannel], skipped: Int) {
        let found = BotKnowWire.items(list)
        let rows = found.items.map { item -> YouBotsChannel in
            let kind = item.kind?.string ?? ""
            let label = YouBotsWire.safe(item.label?.string ?? kind)
            let enabled = item.enabled?.bool ?? false
            return YouBotsChannel(id: item.id, kind: kind, name: YouBotsWire.safe(item.name?.string ?? label), label: label, enabled: enabled,
                                  twoWay: item.twoWay?.bool ?? true, webhook: item.webhook?.bool ?? false,
                                  anyone: item.anyoneMayMessage?.bool ?? false, senders: item.allowedSenders?.count ?? 0,
                                  state: item.status?.state?.string ?? (enabled ? "starting" : "off"))
        }
        return (rows, found.skipped)
    }

    nonisolated static func discordRows(_ list: [BotKnowLossy<YouBotsDiscordDTO>]) -> (rows: [YouBotsDiscord], skipped: Int) {
        let found = BotKnowWire.items(list)
        var rows: [YouBotsDiscord] = []
        for bot in found.items {
            var overrides: [YouBotsOverride] = []
            for entry in BotKnowWire.items(bot.channels).items {
                let label: String = YouBotsWire.safe(entry.label?.string ?? "channel")
                overrides.append(YouBotsOverride(id: entry.id, label: label, mode: entry.mode?.string ?? "normal"))
            }
            let name: String = YouBotsWire.safe(bot.name?.string ?? "Discord bot")
            rows.append(YouBotsDiscord(id: bot.id, name: name, hasToken: bot.hasToken?.bool ?? false,
                                       hasAllowedUser: bot.allowedUserId?.isSet == true, hasVoice: bot.voiceChannelId?.isSet == true,
                                       overrides: overrides))
        }
        return (rows, found.skipped)
    }

    // MARK: Showing

    /// The housekeeping form follows the desktop until the person edits it; an edit that now equals the desktop's is no edit.
    private func showHousekeeping(_ fresh: YouBotsHousekeeping?) {
        housekeepingFilled = fresh
        guard let fresh else { return }
        // What an edit was made from (`fromDays`, `fromMegabytes`) is never moved by a read.
        if housekeepingEdits.days == fresh.days {
            housekeepingEdits.days = nil
            housekeepingEdits.fromDays = nil
        }
        if housekeepingEdits.megabytes == Self.wholeMegabytes(fresh.megabytes) {
            housekeepingEdits.megabytes = nil
            housekeepingEdits.fromMegabytes = nil
        }
    }

    nonisolated static func wholeMegabytes(_ value: Double) -> Int { max(1, Int(value.rounded())) }

    /// An alias the person is typing stays through a read; one that now equals the desktop's is no edit.
    private func showApps(_ fresh: [YouBotsApp]) {
        apps = fresh
        for (key, text) in aliasEdits {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let now = fresh.first(where: { $0.id == parts[0] })?.accounts.first(where: { $0.id == parts[1] })?.alias
            if now == nil || now == text { aliasEdits[key] = nil }
        }
    }

    // MARK: Writing

    private static func isMissing(_ error: Error) -> Bool {
        if case .server(status: 404, _) = error as? APIError { return true }
        return false
    }

    private static func isConflict(_ error: Error) -> Bool {
        if case .server(status: 409, _) = error as? APIError { return true }
        return false
    }

    /// The desktop refused the request (or it was never sent), so it certainly did not happen. Anything else (not
    /// reached, timed out, an answer this app could not read, a server error) may have come after it did.
    private static func wasRefused(_ error: Error) -> Bool {
        if error is YouBotsNotSent { return true }
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status)
        case .offline, .unreadable: return false
        }
    }

    private static func words(_ error: Error) -> String {
        (error as? YouBotsNotSent)?.plain ?? YouBotsWire.safe(error.plainWords)
    }

    /// Send one change, once. `send` makes the call; `check` reads the desktop and answers whether the change is there
    /// (nil: it cannot tell), used only when the answer was lost; `done` shows the change. Nothing is put back by hand
    /// and no second tap is offered blind: afterwards the part is read again and what the desktop really has is shown.
    private func change(_ part: YouBotsPart, key: String, words: YouBotsWords,
                        send: (APIClient, String) async throws -> Void,
                        check: (APIClient) async throws -> Bool?,
                        done: () -> Void) async {
        guard isLive else { return }
        guard Self.accountKey == liveAccount else {
            followConnection()
            return
        }
        guard !busy.contains(key), unconfirmed[part]?.contains(key) != true else { return }
        let account = liveAccount
        busy.insert(key)
        writing[part, default: 0] += 1
        notice[part] = nil
        defer {
            if liveAccount == account {
                busy.remove(key)
                writing[part, default: 1] -= 1
                writes[part, default: 0] += 1
                Task { if self.stillLive(account) { await self.read(part) } }
            }
        }
        do {
            try ensureLive(account)
            let client = try liveClient()
            try ensureLive(account)
            try await send(client, account)
            guard stillLive(account) else { return }
            done()
            Haptics.success()
            YouStore.shared.say(words.done)
        } catch {
            guard stillLive(account) else { return }
            if !(error is YouBotsNotSent) { Connection.shared.note(error) }
            guard stillLive(account) else { return }
            if words.missingIsDone, Self.isMissing(error) {
                done()
                YouStore.shared.say(words.done)
                return
            }
            if Self.isConflict(error) {
                notice[part] = words.failed + " " + words.conflict
                return
            }
            if Self.wasRefused(error) {
                notice[part] = words.failed + " " + Self.words(error)
                return
            }
            // The change may have reached the desktop before the answer was lost: look.
            let landed: Bool?
            do {
                landed = try await check(try liveClient())
            } catch {
                landed = nil
            }
            guard stillLive(account) else { return }
            switch landed {
            case true?:
                done()
                YouStore.shared.say(words.done)
            case false?:
                if let api = error as? APIError, case .offline = api {
                    // No answer in time: the change may still be on its way. Never "has not happened".
                    unconfirmed[part, default: []].insert(key)
                    notice[part] = "Your desktop did not confirm this in time, and it may still be saving. What it has now is shown. Look again in a moment before trying again."
                } else {
                    notice[part] = "Your desktop did not confirm this, and it has not happened there. " + Self.words(error)
                }
            case nil:
                unconfirmed[part, default: []].insert(key)
                notice[part] = "Your desktop did not confirm this, and it could not be checked. Look again in a moment before trying again."
            }
        }
    }

    // MARK: Skills

    /// Turn a library skill off, against the revision the person saw. The phone never turns one on: that needs a full
    /// read of its text, which is done in Kairos on the desktop.
    func skillOff(_ name: String, revision: String) async {
        guard let row = skills.first(where: { $0.id == name }), row.enabled else { return }
        await change(.library, key: "skill:" + name,
                     words: YouBotsWords(done: "/\(name) is off.", failed: "/\(name) was not turned off.", missingIsDone: true,
                                         conflict: "It changed on your desktop, so nothing was changed. What your desktop has now is shown."),
                     send: { client, _ in try await client.youBotsSkillOff(name, revision: revision) },
                     check: { client in
                         let fresh = BotKnowWire.items(try await client.youBotsLibrary().skills).items
                         guard let found = fresh.first(where: { $0.name == name }), let on = found.enabled?.bool else {
                             return fresh.contains(where: { $0.name == name }) ? nil : true
                         }
                         return !on
                     },
                     done: {
                         if let index = skills.firstIndex(where: { $0.id == name }) {
                             skills[index].enabled = false
                             skills[index].effective = false
                         }
                     })
    }

    // MARK: Channels

    /// Turn a channel off. The phone never turns one on.
    func connectorOff(_ id: String) async {
        guard let row = channels.first(where: { $0.id == id }), row.enabled else { return }
        await change(.connectors, key: "connector:" + id,
                     words: YouBotsWords(done: "\(row.name) is off.", failed: "\(row.name) was not turned off.", missingIsDone: true),
                     send: { client, _ in try await client.youBotsConnectorOff(id) },
                     check: { client in
                         let fresh = Self.channelRows(try await client.youBotsConnectors()).rows
                         guard let found = fresh.first(where: { $0.id == id }) else { return true }
                         return !found.enabled
                     },
                     done: {
                         if let index = channels.firstIndex(where: { $0.id == id }) {
                             channels[index].enabled = false
                             channels[index].state = "off"
                         }
                     })
    }

    private static func testKey(_ account: String, _ id: String) -> String { account + "|" + id }

    /// A test whose answer was lost is also kept on the phone, so it stays off after the app is closed and opened again.
    /// The key is a SHA-256 of the account and channel: no address, name or id is stored.
    private static func markKey(_ key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return "YouBots.unconfirmedTest." + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isMarked(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: markKey(key)) }

    private static func mark(_ key: String) { UserDefaults.standard.set(true, forKey: markKey(key)) }

    private static func unmark(_ key: String) { UserDefaults.standard.removeObject(forKey: markKey(key)) }

    private func currentTest(_ key: String) -> YouBotsTestState? {
        tests[key] ?? (Self.isMarked(key) ? .unconfirmed : nil)
    }

    /// Where this channel's test stands for the paired account.
    func testState(_ id: String) -> YouBotsTestState? { currentTest(Self.testKey(Self.accountKey, id)) }

    /// The person looked in the channel themselves and allows one more test.
    func allowAnotherTest(_ id: String) {
        let key = Self.testKey(Self.accountKey, id)
        guard currentTest(key) == .unconfirmed else { return }
        Self.unmark(key)
        tests[key] = nil
    }

    /// Send one test message through a channel. It is a REAL message and has no request id, so: it is marked as sending
    /// before the request leaves; once the desktop has answered, it can be sent again by a new tap; if no answer came
    /// (it may have been sent), it is never sent again from this phone, however the screen is left or opened again.
    func sendTest(_ id: String) async {
        followConnection()
        guard isLive else { return }
        let account = liveAccount
        let key = Self.testKey(account, id)
        switch currentTest(key) {
        case .sending?, .unconfirmed?: return
        default: break
        }
        guard let row = channels.first(where: { $0.id == id }), row.enabled, row.state != "error" else { return }
        // Marked before the request leaves; dropped only when the desktop answers, or the request never left.
        Self.mark(key)
        tests[key] = .sending
        do {
            _ = try YouBotsWire.pathID(id)
            let client = try liveClient()
            try await client.youBotsConnectorTest(id)
            tests[key] = .sent
            Self.unmark(key)
            if stillLive(account) {
                Haptics.success()
            }
        } catch {
            if error is YouBotsNotSent {
                tests[key] = .refused("Nothing was sent. The channel's id could not be read.")
                Self.unmark(key)
            } else if let api = error as? APIError {
                switch api {
                case .notPaired, .badAddress, .unauthorized:
                    tests[key] = .refused("Nothing was sent. This phone is not paired with your desktop.")
                    Self.unmark(key)
                case .server(let status, _):
                    // The desktop answered. Its own words are never shown (they can carry an address).
                    Self.unmark(key)
                    switch status {
                    case 400: tests[key] = .refused("Not sent. Say where this channel sends notifications, in Kairos on your desktop, first.")
                    case 404: tests[key] = .refused("Not sent. Your desktop does not have this channel any more.")
                    case 502: tests[key] = .refused("Your desktop says sending failed. It may still have arrived: look in the channel before sending another.")
                    case 403: tests[key] = .refused("Not sent. Your account on your desktop is not allowed to do that.")
                    default: tests[key] = .refused("Not sent. Your desktop refused it (error \(status)).")
                    }
                case .offline, .unreadable:
                    tests[key] = .unconfirmed
                }
            } else {
                // Stopped or unknown: the request may have left.
                tests[key] = .unconfirmed
            }
            if stillLive(account), tests[key] != .unconfirmed { Haptics.thud() }
            if stillLive(account), !(error is YouBotsNotSent) { Connection.shared.note(error) }
        }
    }

    // MARK: Connected apps

    /// Turn an MCP tool server off. The phone never turns one on.
    func mcpOff(_ id: String) async {
        guard let row = apps.first(where: { $0.id == id }), row.isMCP, row.enabled else { return }
        await change(.apps, key: "mcp:" + id,
                     words: YouBotsWords(done: "\(row.name) is off.", failed: "\(row.name) was not turned off.", missingIsDone: true),
                     send: { client, _ in try await client.youBotsMcpOff(id) },
                     check: { client in
                         let fresh = Self.appRows(try await client.youBotsApps()).rows
                         guard let found = fresh.first(where: { $0.id == id }) else { return true }
                         return !found.enabled
                     },
                     done: {
                         if let index = apps.firstIndex(where: { $0.id == id }) {
                             apps[index].enabled = false
                             apps[index].state = "off"
                         }
                     })
    }

    private static func aliasKey(_ app: String, _ account: String) -> String { app + "|" + account }

    /// The alias the form shows: what the person typed, else the desktop's.
    func aliasShown(_ app: String, _ account: YouBotsAccount) -> String {
        aliasEdits[Self.aliasKey(app, account.id)] ?? account.alias
    }

    func aliasEdited(_ app: String, _ account: String) -> Bool {
        aliasEdits[Self.aliasKey(app, account)] != nil
    }

    func editAlias(_ app: String, _ account: String, to text: String) {
        guard let base = apps.first(where: { $0.id == app })?.accounts.first(where: { $0.id == account }) else { return }
        aliasEdits[Self.aliasKey(app, account)] = text == base.alias ? nil : text
    }

    /// Name one account. Only an alias the person changed is sent, and only that.
    func saveAlias(_ app: String, _ account: String) async {
        let key = Self.aliasKey(app, account)
        guard let typed = aliasEdits[key] else { return }
        guard let alias = YouBotsWire.alias(typed) else {
            notice[.apps] = "An alias is 1 to 64 characters."
            Haptics.thud()
            return
        }
        let box = YouBotsSentBox()
        box.alias = alias
        await change(.apps, key: "alias:" + key,
                     words: YouBotsWords(done: "Alias saved.", failed: "The alias was not saved.",
                                         conflict: "Another account of this app already has that alias."),
                     send: { client, _ in try await client.youBotsSetAlias(app: app, account: account, alias: alias) },
                     check: { client in
                         let fresh = Self.appRows(try await client.youBotsApps()).rows
                         guard let found = fresh.first(where: { $0.id == app })?.accounts.first(where: { $0.id == account }) else { return nil }
                         return found.alias == box.alias
                     },
                     done: { aliasEdits[key] = nil })
    }

    // MARK: Bot computers

    /// Put one bot's computer to sleep (admin accounts). A bot wakes it when it needs it.
    func sleepComputer(_ botID: String) async {
        guard let row = computers.first(where: { $0.id == botID }), row.running else { return }
        await change(.computers, key: "sleep:" + botID,
                     words: YouBotsWords(done: "\(row.name)'s computer is asleep.", failed: "\(row.name)'s computer was not put to sleep.",
                                         missingIsDone: true),
                     send: { client, _ in try await client.youBotsSleep(botID) },
                     check: { client in
                         let fresh = Self.computerRows(try await client.youBotsComputers()).rows
                         guard let found = fresh.first(where: { $0.id == botID }) else { return true }
                         return !found.running
                     },
                     done: {
                         if let index = computers.firstIndex(where: { $0.id == botID }) {
                             computers[index].running = false
                             computers[index].takenOver = false
                         }
                     })
    }

    // MARK: Housekeeping

    /// What the form shows: the desktop's values with the person's edits on top.
    var housekeepingShown: (days: Int, megabytes: Int)? {
        guard let base = housekeepingFilled else { return nil }
        return (housekeepingEdits.days ?? base.days, housekeepingEdits.megabytes ?? Self.wholeMegabytes(base.megabytes))
    }

    /// A saved edit would lower a value, so older trace details are deleted at the next daily cleanup.
    var housekeepingLowers: Bool {
        guard let base = housekeepingFilled else { return false }
        if let days = housekeepingEdits.days, days < base.days { return true }
        if let megabytes = housekeepingEdits.megabytes, megabytes < Self.wholeMegabytes(base.megabytes) { return true }
        return false
    }

    func editHousekeeping(days: Int? = nil, megabytes: Int? = nil) {
        guard let base = housekeepingFilled else { return }
        if let days {
            if days == base.days {
                housekeepingEdits.days = nil
                housekeepingEdits.fromDays = nil
            } else {
                if housekeepingEdits.days == nil { housekeepingEdits.fromDays = base.days }
                housekeepingEdits.days = days
            }
        }
        if let megabytes {
            let whole = Self.wholeMegabytes(base.megabytes)
            if megabytes == whole {
                housekeepingEdits.megabytes = nil
                housekeepingEdits.fromMegabytes = nil
            } else {
                if housekeepingEdits.megabytes == nil { housekeepingEdits.fromMegabytes = whole }
                housekeepingEdits.megabytes = megabytes
            }
        }
    }

    /// Save housekeeping. The route resets a value it is not sent, so both are always sent: the desktop's own, read
    /// again just before, with only the person's edits on top.
    func saveHousekeeping() async {
        guard !housekeepingEdits.isEmpty, housekeepingFilled != nil else { return }
        let edits = housekeepingEdits
        let box = YouBotsSentBox()
        await change(.housekeeping, key: "housekeeping",
                     words: YouBotsWords(done: "Saved. Applies on the next daily cleanup.", failed: "Housekeeping was not saved."),
                     send: { client, account in
                         let fresh: YouBotsHousekeeping?
                         do {
                             fresh = Self.housekeepingState(try await client.youBotsHousekeeping())
                         } catch {
                             throw YouBotsNotSent(plain: "Housekeeping could not be read first, so nothing was sent. " + YouBotsWire.safe(error.plainWords))
                         }
                         try ensureLive(account)
                         guard let base = fresh else {
                             throw YouBotsNotSent(plain: "Your desktop's housekeeping could not be read in full, so nothing was sent.")
                         }
                         // A field the person edited that the desktop changed since they first edited it is never
                         // overwritten unseen. The compare is with the value the edit was made from, which no read
                         // under the open form moves.
                         let wholeNow = Self.wholeMegabytes(base.megabytes)
                         let daysMoved = edits.days != nil && base.days != edits.fromDays
                         let sizeMoved = edits.megabytes != nil && wholeNow != edits.fromMegabytes
                         if daysMoved || sizeMoved {
                             // The person is told what the desktop has now, so a second Save carries their edits on top of it.
                             if edits.days != nil { housekeepingEdits.fromDays = base.days }
                             if edits.megabytes != nil { housekeepingEdits.fromMegabytes = wholeNow }
                             throw YouBotsNotSent(plain: "Housekeeping changed on your desktop (it now keeps \(base.days) days and \(wholeNow) MB), so nothing was sent. Your edits are kept here. Save again to use them.")
                         }
                         let next = YouBotsHousekeeping(days: edits.days ?? base.days,
                                                        megabytes: edits.megabytes.map(Double.init) ?? base.megabytes)
                         box.housekeeping = next
                         _ = try await client.youBotsSetHousekeeping(days: next.days, megabytes: next.megabytes)
                     },
                     check: { client in
                         // What was sent, compared with the desktop (never with the form as it is now).
                         guard let sent = box.housekeeping, let now = Self.housekeepingState(try await client.youBotsHousekeeping()) else { return nil }
                         return now == sent
                     },
                     done: { housekeepingEdits = YouBotsHousekeepingEdits() })
    }

    // MARK: Discord bots

    /// Set one channel override to silent, or from open to normal. The phone never sets one to open, and never makes a
    /// silent one answer again: on the desktop that can open the channel to everyone when the bot has no allowed user.
    func setOverrideMode(bot: String, entry: String, mode: String) async {
        guard mode == "normal" || mode == "silent" else { return }
        guard let cachedBot = discordBots.first(where: { $0.id == bot }),
              let current = cachedBot.overrides.first(where: { $0.id == entry }), current.mode != mode else { return }
        let moved = "#\(current.label) changed on your desktop, so nothing was sent. What your desktop has now is shown."
        guard current.mode == "open" || mode == "silent" else {
            notice[.discord] = moved
            return
        }
        await change(.discord, key: "override:" + entry,
                     words: YouBotsWords(done: "#\(current.label) is \(mode) now.", failed: "#\(current.label) was not changed.", missingIsDone: false),
                     send: { client, account in
                         // The screen can be old and the desktop's route takes no expected mode. So the bots are read
                         // again here, and the change leaves only when the entry is still in the mode the person saw
                         // (and, for normal, the bot's allowed user is as the confirm said). A silent entry is never
                         // made to answer again, whatever the screen showed.
                         let rows: [YouBotsDiscord]
                         do {
                             rows = Self.discordRows(try await client.youBotsDiscordBots()).rows
                         } catch {
                             throw YouBotsNotSent(plain: "Your desktop could not be read first, so nothing was sent.")
                         }
                         try ensureLive(account)
                         guard let freshBot = rows.first(where: { $0.id == bot }),
                               let now = freshBot.overrides.first(where: { $0.id == entry }) else {
                             throw YouBotsNotSent(plain: "This override is not on your desktop any more, so nothing was sent.")
                         }
                         guard now.mode == current.mode, now.mode == "open" || mode == "silent",
                               mode != "normal" || freshBot.hasAllowedUser == cachedBot.hasAllowedUser else {
                             throw YouBotsNotSent(plain: moved)
                         }
                         try await client.youBotsOverrideMode(bot: bot, entry: entry, mode: mode)
                     },
                     check: { client in
                         let fresh = Self.discordRows(try await client.youBotsDiscordBots()).rows
                         guard let found = fresh.first(where: { $0.id == bot })?.overrides.first(where: { $0.id == entry }) else { return nil }
                         return found.mode == mode
                     },
                     done: {
                         if let at = discordBots.firstIndex(where: { $0.id == bot }),
                            let index = discordBots[at].overrides.firstIndex(where: { $0.id == entry }) {
                             discordBots[at].overrides[index].mode = mode
                         }
                     })
    }

    /// Remove one channel override. The phone cannot add one back, and never removes a silent one: that would let the
    /// bot answer in that channel again.
    func removeOverride(bot: String, entry: String) async {
        guard let cachedBot = discordBots.first(where: { $0.id == bot }),
              let current = cachedBot.overrides.first(where: { $0.id == entry }) else { return }
        let moved = "#\(current.label) changed on your desktop, so nothing was sent. What your desktop has now is shown."
        guard current.mode != "silent" else {
            notice[.discord] = moved
            return
        }
        await change(.discord, key: "override:" + entry,
                     words: YouBotsWords(done: "#\(current.label) was removed.", failed: "#\(current.label) was not removed.", missingIsDone: true),
                     send: { client, account in
                         // Read again first, as for a mode change: removing an entry that was set to silent on the
                         // desktop since the screen was read would make the bot answer there again.
                         let rows: [YouBotsDiscord]
                         do {
                             rows = Self.discordRows(try await client.youBotsDiscordBots()).rows
                         } catch {
                             throw YouBotsNotSent(plain: "Your desktop could not be read first, so nothing was sent.")
                         }
                         try ensureLive(account)
                         guard let freshBot = rows.first(where: { $0.id == bot }),
                               let now = freshBot.overrides.first(where: { $0.id == entry }) else {
                             throw YouBotsNotSent(plain: "This override is not on your desktop any more, so nothing was sent.")
                         }
                         guard now.mode != "silent", now.mode == current.mode,
                               freshBot.hasAllowedUser == cachedBot.hasAllowedUser else {
                             throw YouBotsNotSent(plain: moved)
                         }
                         try await client.youBotsRemoveOverride(bot: bot, entry: entry)
                     },
                     check: { client in
                         let fresh = Self.discordRows(try await client.youBotsDiscordBots()).rows
                         guard let found = fresh.first(where: { $0.id == bot }) else { return nil }
                         return !found.overrides.contains(where: { $0.id == entry })
                     },
                     done: {
                         if let at = discordBots.firstIndex(where: { $0.id == bot }) {
                             discordBots[at].overrides.removeAll { $0.id == entry }
                         }
                     })
    }

    /// Turn a Discord bot's voice channel off. The phone cannot set one.
    func clearVoice(bot: String) async {
        guard let current = discordBots.first(where: { $0.id == bot }), current.hasVoice else { return }
        await change(.discord, key: "voice:" + bot,
                     words: YouBotsWords(done: "Voice is off for \(current.name).", failed: "Voice was not turned off."),
                     send: { client, _ in try await client.youBotsClearVoice(bot: bot) },
                     check: { client in
                         let fresh = Self.discordRows(try await client.youBotsDiscordBots()).rows
                         guard let found = fresh.first(where: { $0.id == bot }) else { return nil }
                         return !found.hasVoice
                     },
                     done: {
                         if let at = discordBots.firstIndex(where: { $0.id == bot }) { discordBots[at].hasVoice = false }
                     })
    }

    // MARK: The first way bots call you

    /// Make one way the first in Reach me's call order, through Reach me's own store: one write of the whole order
    /// (`makeFirst`), with its compare-before-send and lost-answer check. A way that is not in the order is added only
    /// when the desktop says it is set up. Reach me says what happened.
    func setFirstCall(_ way: String) async {
        let voice = YouVoiceLive.shared
        guard !callChanging, let view = voice.reach, view.call.first != way else { return }
        guard view.callChannels.contains(where: { $0.id == way && ($0.ready || view.call.contains(way)) }) else { return }
        callChanging = true
        defer { callChanging = false }
        await voice.makeFirst(.call, way)
    }
}

// MARK: - Small views shared by the paired screens

/// The loading note or the failure with Try again for one part; nothing once it is read. A part the desktop refused for
/// this account gets one plain line.
struct YouBotsLoadLine: View {
    let part: YouBotsPart
    let loading: String
    private let live = YouBotsLive.shared

    var body: some View {
        if live.memberOnly.contains(part) {
            YouAccessLine(text: "Your account on your desktop is not allowed to see this. Ask an admin.")
        } else {
            switch live.load(part) {
            case .failed(let text)?:
                YouAccessLine(text: text, action: "Try again") {
                    Task { await live.read(part) }
                }
            case .loaded?:
                EmptyView()
            default:
                YouAccessLine(text: loading)
            }
        }
    }
}

/// What a change that did not go through left behind, as one sentence.
struct YouBotsNoticeLine: View {
    let part: YouBotsPart
    private let live = YouBotsLive.shared

    var body: some View {
        if let text = live.notice[part] {
            NoteText(text: text, symbol: "exclamationmark.triangle")
        }
    }
}

/// The button on the right of a row with a narrowing change: on its way, not confirmed, or the button.
struct YouBotsChangeButton: View {
    let part: YouBotsPart
    let key: String
    let title: String
    let working: String
    var danger = true
    let action: () -> Void
    private let live = YouBotsLive.shared

    var body: some View {
        if live.busy.contains(key) {
            StatusPill(text: working, tone: .muted)
        } else if live.unconfirmed[part]?.contains(key) == true {
            StatusPill(text: "Not confirmed", tone: .warn)
        } else {
            YouPillButton(title: title, danger: danger, action: action)
        }
    }
}

/// A name that can drive `.sheet(item:)`.
nonisolated struct YouBotsNamed: Identifiable, Hashable, Sendable {
    let id: String
    var other = ""
}
