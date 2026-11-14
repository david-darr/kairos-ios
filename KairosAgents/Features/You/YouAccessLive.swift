import SwiftUI

/// Where one desktop read stands, for one plain sentence on screen.
nonisolated enum YouAccessLoad: Equatable, Sendable {
    case idle, loading, loaded
    case failed(String)
}

/// The parts of You > Account and Access that are read from the paired desktop, each on its own.
nonisolated enum YouAccessPart: Hashable, Sendable {
    case account, devices, permissions, tools, computerUse, computers, computerStatus, forge
}

/// A saved permission rule, as the screen shows it.
nonisolated struct YouAccessRule: Identifiable, Hashable, Sendable {
    let id: String
    var tool: String
    /// The rule's text as the desktop keeps it, with what looks secret masked (display only, never sent back;
    /// the rule is revoked by its id). Nil covers the whole tool.
    var content: String?
    var allowed: Bool
    var scope: String
    var who: String
    var date: Date?
}

/// One line of the desktop's recent decisions, newest first.
nonisolated struct YouAccessDecisionLine: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var detail: String
}

nonisolated struct YouAccessDevice: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var model: String
    var paired: Date?
    var lastSeen: Date?
    var current: Bool
}

nonisolated struct YouAccessComputer: Identifiable, Hashable, Sendable {
    let owner: String
    var title: String
    var ownerName: String
    var desktop: Bool
    var takenOver: Bool
    var id: String { owner }
}

nonisolated struct YouAccessProfile: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var running: Bool
}

/// The account flags from /api/auth/status. Never a PIN, password or key: only whether each is set.
nonisolated struct YouAccessAccountFlags: Hashable, Sendable {
    var machineAccess: Bool?
    var twoStep: Bool?
    var switchPin: Bool?
    var color: String?
}

nonisolated struct YouAccessTools: Hashable, Sendable {
    var available: [String]
    var disabled: Set<String>
    var extra: [String]
}

nonisolated struct YouAccessDocker: Hashable, Sendable {
    var available: Bool?
    var reason: String?
    var imageReady: Bool?
}

/// Rule and decision text with what looks secret replaced by "••••", for display only. It is never sent back to the
/// desktop (a rule is revoked by its id). Masked: the user and password of an address (`scheme://user:pass@host`
/// shows as `scheme://host`), query values, what follows `Bearer ` or `token=`, `key=`, `secret=`, `password=`,
/// and any run of 24 or more of letters, digits, `-`, `_`, `+`, `/`, `=` holding both a letter and a digit.
nonisolated func youAccessMasked(_ text: String) -> String {
    let dots = "••••"
    var out = text
    func replace(_ pattern: String, _ template: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
        out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
    }
    replace(#"([a-z][a-z0-9+.\-]*://)[^\s/@?#]+@"#, "$1")
    replace(#"(bearer\s+)[^\s'"]+"#, "$1" + dots)
    replace(#"((?:token|key|secret|password)\s*=\s*)(?:"[^"]*"|'[^']*'|[^\s&#'"]+)"#, "$1" + dots)
    replace(#"([?&][^\s=&#?]+=)[^\s&#]+"#, "$1" + dots)
    guard let long = try? NSRegularExpression(pattern: #"[A-Za-z0-9\-_+/=]{24,}"#) else { return out }
    let whole = out as NSString
    var result = ""
    var at = 0
    for match in long.matches(in: out, range: NSRange(location: 0, length: whole.length)) {
        let run = whole.substring(with: match.range)
        guard run.contains(where: \.isLetter), run.contains(where: \.isNumber) else { continue }
        result += whole.substring(with: NSRange(location: at, length: match.range.location - at)) + dots
        at = match.range.location + match.range.length
    }
    return result + whole.substring(from: at)
}

/// A change stopped before anything was sent to the desktop.
nonisolated struct YouAccessNotSent: Error, Sendable {
    let plain: String
}

/// What a whole-object change sent, shared by the closures of one change.
private final class YouAccessSentBox {
    var values: YouAccessComputerUseValues?
}

/// The words for one narrowing change.
private struct YouAccessWords {
    var done: String
    var failed: String
    /// The desktop answered 404: what the change wanted is already true.
    var missingIsDone = false
}

/// The paired desktop behind You > Account, Accounts on this device, Permissions, Agent tools, Computer use,
/// Remote access (its paired phones) and Forge settings. Unpaired, nothing here runs and every screen shows its
/// sample data. Paired, only narrowing changes are sent: revoke a rule, unpair a phone, stop a computer, switch a
/// tool off, turn computer use off, turn the Forge terminal setting off. Nothing that widens access, and no
/// password, PIN, key or token, is ever sent or kept here.
@Observable
final class YouAccessLive {
    static let shared = YouAccessLive()

    private(set) var loads: [YouAccessPart: YouAccessLoad] = [:]
    private(set) var flags: YouAccessAccountFlags?
    private(set) var devices: [YouAccessDevice] = []
    private(set) var rules: [YouAccessRule] = []
    private(set) var decisions: [YouAccessDecisionLine] = []
    private(set) var skippedRules = 0
    private(set) var tools: YouAccessTools?
    private(set) var computerUse: YouAccessComputerUseValues?
    /// The desktop sent a computer-use object this app could not read in full.
    private(set) var computerUseUnreadable = false
    private(set) var stepsDays: Int?
    private(set) var computers: [YouAccessComputer] = []
    private(set) var docker: YouAccessDocker?
    private(set) var profiles: [YouAccessProfile] = []
    /// Only the last folder of the Forge root; the whole personal path never stays on the phone.
    private(set) var forgeFolder: String?
    private(set) var forgeTerminalRemote: Bool?
    /// Changes on their way: "rule:<id>", "device:<id>", "computer:<owner>", "tool:<name>", "computerUse",
    /// "forgeTerminal", "thisPhone".
    private(set) var busy: Set<String> = []
    /// Changes the desktop did not confirm and that could not be checked. No second tap until a read shows them.
    private(set) var unconfirmed: [YouAccessPart: Set<String>] = [:]
    /// One plain sentence per part after a change that did not go through.
    var notice: [YouAccessPart: String] = [:]
    /// Unpairing this phone did not go through.
    var thisPhoneNotice: String?
    /// Admin-only parts the desktop answered 403: the screen shows the member line.
    private(set) var memberOnly: Set<YouAccessPart> = []

    /// The parts only an admin may read.
    private static let adminOnly: Set<YouAccessPart> = [.tools, .computerStatus, .forge]

    /// Show the member line for this admin-only part: the cached flag says member, or the desktop answered 403.
    func asMember(_ part: YouAccessPart) -> Bool { !Self.isAdmin || memberOnly.contains(part) }

    @ObservationIgnored private var liveAccount = "sample"
    @ObservationIgnored private var reads: [YouAccessPart: Int] = [:]
    @ObservationIgnored private var writes: [YouAccessPart: Int] = [:]

    private init() {}

    // MARK: The connection

    /// A key that changes when the phone is paired or unpaired, the desktop comes back,
    /// or a different desktop or account is paired.
    static var connectionKey: String {
        let connection = Connection.shared
        return "\(connection.usesSampleData)-\(connection.isConnected)-\(accountKey)"
    }

    /// Which desktop and which account the data belongs to.
    static var accountKey: String {
        let connection = Connection.shared
        guard !connection.usesSampleData, let desktop = connection.desktop else { return "sample" }
        return desktop.address + "|" + desktop.username
    }

    /// Paired: the screens show only what the desktop sends.
    static var isPaired: Bool { !Connection.shared.usesSampleData }

    /// The paired account is an admin (as last told by /api/phone/session).
    static var isAdmin: Bool { Connection.shared.desktop?.isAdmin ?? false }

    /// The account this phone is paired as, drawn like the sample accounts. It never holds a PIN.
    static var pairedAccount: DeviceAccount? {
        guard isPaired, let desktop = Connection.shared.desktop else { return nil }
        let name = desktop.username.isEmpty ? "You" : desktop.username
        return DeviceAccount(id: "paired", name: name, colorHex: YouAccessWire.colorHex(desktop.color), isAdmin: desktop.isAdmin)
    }

    private var isLive: Bool { Self.isPaired }

    private func stillLive(_ account: String) -> Bool {
        isLive && liveAccount == account && Self.accountKey == account
    }

    private static let desktopChanged = "Your paired desktop changed. Try again."

    /// Drop everything read from another desktop or account.
    func followConnection() {
        let key = Self.accountKey
        guard key != liveAccount else { return }
        loads = [:]
        flags = nil
        devices = []
        rules = []
        decisions = []
        skippedRules = 0
        tools = nil
        computerUse = nil
        computerUseUnreadable = false
        stepsDays = nil
        computers = []
        docker = nil
        profiles = []
        forgeFolder = nil
        forgeTerminalRemote = nil
        busy = []
        unconfirmed = [:]
        notice = [:]
        thisPhoneNotice = nil
        memberOnly = []
        reads = [:]
        writes = [:]
        liveAccount = key
    }

    private func liveClient() throws -> APIClient {
        guard let client = Connection.shared.client else { throw APIError.notPaired }
        return client
    }

    func load(_ part: YouAccessPart) -> YouAccessLoad? { loads[part] }

    // MARK: Reading

    /// Read one part. An older read never replaces newer state, a read that was on its way while a change finished
    /// is read again, and a cancelled read changes nothing.
    func read(_ part: YouAccessPart) async {
        followConnection()
        guard isLive else { return }
        switch part {
        case .account:
            await read(part, "Your account could not be read.", fetch: { try await $0.youAccessAuthStatus() }) { dto in
                self.flags = YouAccessAccountFlags(machineAccess: dto.machineAccess?.bool, twoStep: dto.totpEnabled?.bool,
                                                   switchPin: dto.switchPin?.bool, color: dto.color?.string)
            }
        case .devices:
            await read(part, "Your paired phones could not be read.", fetch: { try await $0.youAccessDevices() }) { dto in
                self.showDevices(dto)
            }
        case .permissions:
            await read(part, "Your permissions could not be read.", fetch: { try await $0.youAccessPermissions() }) { dto in
                self.showPermissions(dto)
            }
        case .tools:
            await read(part, "The agent tools could not be read.", fetch: { try await $0.youAccessAgentTools() }) { dto in
                self.showTools(dto)
            }
        case .computerUse:
            await read(part, "The computer use settings could not be read.", fetch: { try await $0.youAccessSettings() }) { dto in
                guard !self.busy.contains("computerUse") else { return }
                self.computerUse = dto.computerUse?.values
                self.computerUseUnreadable = dto.computerUse?.values == nil
                self.stepsDays = dto.computerStepsDays?.int
            }
        case .computers:
            await read(part, "The running computers could not be read.", fetch: { try await $0.youAccessComputers() }) { dto in
                self.showComputers(dto)
            }
        case .computerStatus:
            await read(part, "Docker and the kept profiles could not be read.", fetch: { try await $0.youAccessComputerStatus() }) { dto in
                self.docker = YouAccessDocker(available: dto.dockerAvailable?.bool, reason: dto.dockerReason?.string,
                                              imageReady: dto.imageReady?.bool)
                self.profiles = dto.profiles.map {
                    YouAccessProfile(id: $0.id, name: $0.name?.string ?? $0.id, running: $0.running?.bool ?? false)
                }
            }
        case .forge:
            await read(part, "The Forge settings could not be read.", fetch: { client -> (String?, Bool?) in
                let root = try await client.youAccessForgeRoot()
                let terminal = try await client.youAccessForgeTerminal()
                return (root.folderName, terminal.forgeTerminalRemote?.bool)
            }) { pair in
                self.forgeFolder = pair.0
                if !self.busy.contains("forgeTerminal") { self.forgeTerminalRemote = pair.1 }
            }
        }
    }

    @discardableResult
    private func read<T>(_ part: YouAccessPart, _ failure: String, fetch: (APIClient) async throws -> T,
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
                guard before == (writes[part] ?? 0) else { continue }
                memberOnly.remove(part)
                apply(value)
                // A real read shows what the desktop has, so a change it did not confirm can be judged again.
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
                if Self.adminOnly.contains(part), case .server(status: 403, _)? = error as? APIError {
                    // The desktop says this account is not an admin, whatever the cached flag says.
                    memberOnly.insert(part)
                    loads[part] = .loaded
                    return false
                }
                loads[part] = .failed(failure + " " + error.plainWords)
                return false
            }
        }
        guard stillLive(account), mine == reads[part] else { return false }
        if loads[part] != .loaded { loads[part] = .failed(failure + " It kept changing while it was read. Try again.") }
        return false
    }

    private func showDevices(_ dto: YouAccessDevicesDTO) {
        let kept = Dictionary(devices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var fresh = dto.devices.map { device in
            YouAccessDevice(id: device.id, name: device.name?.string ?? "Phone", model: device.model?.string ?? "",
                            paired: YouAccessWire.known(device.createdAt?.date),
                            lastSeen: YouAccessWire.known(device.lastSeenAt?.date),
                            current: device.current?.bool ?? false)
        }
        // A phone with an unpair on its way stays as it was until the desktop answers.
        for (id, device) in kept where busy.contains("device:" + id) && !fresh.contains(where: { $0.id == id }) {
            fresh.append(device)
        }
        devices = fresh
    }

    private func showPermissions(_ dto: YouAccessPermissionsDTO) {
        let kept = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var fresh = Self.rules(from: dto)
        for (id, rule) in kept where busy.contains("rule:" + id) && !fresh.contains(where: { $0.id == id }) {
            fresh.append(rule)
        }
        rules = fresh
        decisions = Self.decisions(from: dto)
        skippedRules = dto.skipped
    }

    private func showTools(_ dto: YouAccessAgentToolsDTO) {
        var disabled = Set(dto.disabledNames)
        // A tool with a switch-off on its way keeps what the person sees until the desktop answers.
        if let old = tools {
            for name in old.available where busy.contains("tool:" + name) {
                if old.disabled.contains(name) { disabled.insert(name) } else { disabled.remove(name) }
            }
        }
        tools = YouAccessTools(available: dto.availableNames, disabled: disabled, extra: dto.extraNames)
    }

    private func showComputers(_ dto: YouAccessRunningListDTO) {
        let kept = Dictionary(computers.map { ($0.owner, $0) }, uniquingKeysWith: { first, _ in first })
        var fresh = dto.computers.map { item in
            YouAccessComputer(owner: item.owner, title: item.title?.string ?? "", ownerName: ownerName(item.owner),
                              desktop: item.desktop?.bool ?? false, takenOver: item.takenOver?.bool ?? false)
        }
        for (owner, computer) in kept where busy.contains("computer:" + owner) && !fresh.contains(where: { $0.owner == owner }) {
            fresh.append(computer)
        }
        computers = fresh
    }

    /// "agent:<id>" is a bot, named when the paired desktop's bots are known here; "chat:<id>" is a chat.
    private func ownerName(_ owner: String) -> String {
        let parts = owner.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return "Unknown" }
        if parts[0] == "agent" {
            let chats = ChatStore.shared
            if !chats.isSample, let bot = chats.bots.first(where: { $0.id == parts[1] }) { return bot.name }
            if let profile = profiles.first(where: { $0.id == parts[1] }) { return profile.name }
            return "A bot"
        }
        return "A chat"
    }

    // MARK: Shaping (also run by the decode checks)

    nonisolated static func rules(from read: YouAccessPermissionsDTO) -> [YouAccessRule] {
        read.rules.map { dto in
            let content = dto.content?.string.flatMap { $0.isEmpty ? nil : youAccessMasked($0) }
            var scope: String
            if let team = dto.teamName?.string, !team.isEmpty {
                scope = "For the \(team) team"
            } else if let bot = dto.botId?.string, !bot.isEmpty {
                scope = dto.scope?.string == "session" ? "For one bot, in one chat" : "For one bot"
            } else if dto.scope?.string == "session" {
                scope = "In one chat, until it ends"
            } else {
                scope = "Everywhere"
            }
            if dto.adminOnly?.bool == true { scope += ", admins only" }
            let by = dto.grantedBy?.string
            let who: String
            if dto.source?.string == "built-in" || by == "jarvis" {
                who = "built in"
            } else if let by, !by.isEmpty {
                who = "granted by \(by)"
            } else {
                who = "granted"
            }
            return YouAccessRule(id: dto.id, tool: dto.tool?.string ?? "A tool", content: content,
                                 allowed: dto.behavior?.string != "deny", scope: scope, who: who,
                                 date: YouAccessWire.time(dto.grantedAt))
        }
    }

    nonisolated static func decisions(from read: YouAccessPermissionsDTO) -> [YouAccessDecisionLine] {
        var seen: [String: Int] = [:]
        var lines: [YouAccessDecisionLine] = []
        for entry in read.audit.reversed() {
            let decision = entry.decision?.string ?? ""
            var title = decisionWord(decision)
            switch entry.scope?.string {
            case "once": title += " once"
            case "session": title += " in this chat"
            case "forever": title += " always"
            default: break
            }
            if let tool = entry.tool?.string, !tool.isEmpty {
                title += " · " + tool
                if let content = entry.content?.string, !content.isEmpty { title += " (\(youAccessMasked(content)))" }
            }
            var detail: [String] = []
            if let at = YouAccessWire.time(entry.at) { detail.append(at.formatted(date: .abbreviated, time: .shortened)) }
            if let by = entry.by?.string, !by.isEmpty { detail.append(by == "jarvis" ? "Kairos" : by) }
            let base = "\(entry.at?.double ?? 0)|\(decision)|\(entry.tool?.string ?? "")"
            let count = seen[base, default: 0]
            seen[base] = count + 1
            lines.append(YouAccessDecisionLine(id: base + "|\(count)", title: title, detail: detail.joined(separator: " · ")))
        }
        return lines
    }

    nonisolated private static func decisionWord(_ decision: String) -> String {
        switch decision {
        case "allow": return "Allowed"
        case "deny": return "Denied"
        case "granted": return "Granted"
        case "revoked": return "Revoked a rule"
        case "chat_mode_changed": return "Changed a chat's mode"
        case "": return "A decision"
        default:
            let words = decision.replacingOccurrences(of: "_", with: " ")
            return String(words.prefix(1)).uppercased() + String(words.dropFirst())
        }
    }

    // MARK: Narrowing changes

    private static func isMissing(_ error: Error) -> Bool {
        if case .server(status: 404, _) = error as? APIError { return true }
        return false
    }

    /// The desktop refused the request (or it was never sent), so it certainly did not happen. Anything else
    /// (not reached, timed out, an answer this app could not read, a server error) may have come after it did.
    private static func wasRefused(_ error: Error) -> Bool {
        if error is YouAccessNotSent { return true }
        guard let api = error as? APIError else { return false }
        switch api {
        case .notPaired, .badAddress, .unauthorized: return true
        case .server(let status, _): return (400..<500).contains(status)
        case .offline, .unreadable: return false
        }
    }

    private static func words(_ error: Error) -> String {
        (error as? YouAccessNotSent)?.plain ?? error.plainWords
    }

    /// Send one narrowing change, once. `send` makes the call; `check` reads the desktop and answers whether the
    /// change is there, used only when the answer was lost; `done` shows the change. Nothing is put back and no
    /// second tap is offered blind: after a lost answer the desktop is read and what it really has is shown.
    private func narrow(_ part: YouAccessPart, key: String, words: YouAccessWords,
                        send: (APIClient, String) async throws -> Void,
                        check: (APIClient) async throws -> Bool,
                        done: () -> Void) async {
        guard isLive else { return }
        guard !busy.contains(key), unconfirmed[part]?.contains(key) != true else { return }
        let account = liveAccount
        busy.insert(key)
        notice[part] = nil
        defer {
            if liveAccount == account {
                busy.remove(key)
                writes[part, default: 0] += 1
                Task { if self.stillLive(account) { await self.read(part) } }
            }
        }
        do {
            try await send(try liveClient(), account)
            guard stillLive(account) else { return }
            done()
            Haptics.success()
            YouStore.shared.say(words.done)
        } catch {
            // An answer for a pairing that has ended never changes the connection.
            guard stillLive(account) else { return }
            if !(error is YouAccessNotSent) { Connection.shared.note(error) }
            guard stillLive(account) else { return }
            if words.missingIsDone, Self.isMissing(error) {
                done()
                YouStore.shared.say(words.done)
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
                notice[part] = "Your desktop did not confirm this, and it has not happened there. " + error.plainWords
            case nil:
                unconfirmed[part, default: []].insert(key)
                notice[part] = "Your desktop did not confirm this, and it could not be checked. Look again in a moment before trying again."
            }
        }
    }

    private func ensureLive(_ account: String) throws {
        guard stillLive(account) else { throw YouAccessNotSent(plain: Self.desktopChanged) }
    }

    /// Revoke a saved rule. Only a rule the list returned is ever sent (the desktop's delete has no owner check).
    func revokeRule(_ id: String) async {
        guard rules.contains(where: { $0.id == id }) else { return }
        await narrow(.permissions, key: "rule:" + id,
                     words: YouAccessWords(done: "Revoked. Kairos asks next time.", failed: "The rule was not revoked.", missingIsDone: true),
                     send: { client, _ in _ = try await client.youAccessRevokeRule(id) },
                     check: { client in
                         let fresh = try await client.youAccessPermissions()
                         return !fresh.rules.contains { $0.id == id }
                     },
                     done: { rules.removeAll { $0.id == id } })
    }

    /// Unpair another of the account's phones. Its token stops working at once.
    func unpairOther(_ id: String) async {
        guard let device = devices.first(where: { $0.id == id }), !device.current else { return }
        await narrow(.devices, key: "device:" + id,
                     words: YouAccessWords(done: "\(device.name) is unpaired.", failed: "\(device.name) was not unpaired.", missingIsDone: true),
                     send: { client, _ in try await client.youAccessUnpair(id) },
                     check: { client in
                         let fresh = try await client.youAccessDevices()
                         return !fresh.devices.contains { $0.id == id }
                     },
                     done: { devices.removeAll { $0.id == id } })
    }

    /// Stop a running computer. A second stop of a closed computer is answered 404, which counts as stopped.
    func stopComputer(_ owner: String) async {
        guard let computer = computers.first(where: { $0.owner == owner }) else { return }
        let name = computer.title.isEmpty ? "The computer" : computer.title
        await narrow(.computers, key: "computer:" + owner,
                     words: YouAccessWords(done: "\(name) stopped.", failed: "\(name) was not stopped.", missingIsDone: true),
                     send: { client, _ in _ = try await client.youAccessStopComputer(owner) },
                     check: { client in
                         let fresh = try await client.youAccessComputers()
                         return !fresh.computers.contains { $0.owner == owner }
                     },
                     done: { computers.removeAll { $0.owner == owner } })
    }

    /// Switch one built-in tool off. The route replaces the whole disabled list, so it is read again just before
    /// and sent back with this one name added; nothing else in it changes.
    func toolOff(_ name: String) async {
        guard let current = tools, current.available.contains(name), !current.disabled.contains(name) else { return }
        await narrow(.tools, key: "tool:" + name,
                     words: YouAccessWords(done: "\(name) is off. Open chats pick it up on their next message.", failed: "\(name) was not switched off."),
                     send: { client, account in
                         let fresh: YouAccessAgentToolsDTO
                         do {
                             fresh = try await client.youAccessAgentTools()
                         } catch {
                             throw YouAccessNotSent(plain: "The tools could not be read first, so nothing was sent. " + error.plainWords)
                         }
                         try ensureLive(account)
                         guard fresh.disabledReadable else {
                             throw YouAccessNotSent(plain: "Your desktop's tool list could not be read in full, so nothing was sent. Switch it off on your desktop.")
                         }
                         var list = fresh.disabledNames
                         guard !list.contains(name) else { return }
                         list.append(name)
                         _ = try await client.youAccessSetDisabledTools(list)
                     },
                     check: { client in
                         let fresh = try await client.youAccessAgentTools()
                         return fresh.disabledNames.contains(name)
                     },
                     done: { _ = tools?.disabled.insert(name) })
    }

    /// Turn computer use off. The route replaces the whole object, so it is read again just before and the other
    /// three values are sent back exactly as the desktop had them.
    func computerUseOff() async {
        guard computerUse?.enabled == true else { return }
        // What was sent, kept to compare with the desktop after a lost answer (never the screen's copy).
        let sent = YouAccessSentBox()
        await narrow(.computerUse, key: "computerUse",
                     words: YouAccessWords(done: "Computer use is off.", failed: "Computer use was not turned off."),
                     send: { client, account in
                         let fresh: YouAccessSettingsDTO
                         do {
                             fresh = try await client.youAccessSettings()
                         } catch {
                             throw YouAccessNotSent(plain: "The settings could not be read first, so nothing was sent. " + error.plainWords)
                         }
                         try ensureLive(account)
                         guard var values = fresh.computerUse?.values else {
                             throw YouAccessNotSent(plain: "Your desktop's computer use settings could not be read in full, so nothing was sent. Turn it off on your desktop.")
                         }
                         guard values.enabled else {
                             sent.values = values
                             return
                         }
                         values.enabled = false
                         sent.values = values
                         _ = try await client.youAccessSetComputerUse(values)
                     },
                     check: { client in
                         // Off is what was asked; the other three may have changed on the desktop since.
                         let fresh = try await client.youAccessSettings()
                         // Unreadable: it could not be checked (never "it has not happened").
                         guard let enabled = fresh.computerUse?.enabled?.bool else { throw APIError.unreadable("computer use") }
                         if !enabled { sent.values = fresh.computerUse?.values }
                         return !enabled
                     },
                     done: {
                         if let values = sent.values { computerUse = values } else { computerUse?.enabled = false }
                     })
    }

    /// Turn off "Allow the terminal over Remote Access". The desktop also closes terminals opened remotely.
    func forgeTerminalOff() async {
        guard forgeTerminalRemote == true else { return }
        await narrow(.forge, key: "forgeTerminal",
                     words: YouAccessWords(done: "Terminals stay on the desktop now.", failed: "The terminal setting was not turned off."),
                     send: { client, _ in _ = try await client.youAccessForgeTerminalOff() },
                     check: { client in (try await client.youAccessForgeTerminal()).forgeTerminalRemote?.bool == false },
                     done: { forgeTerminalRemote = false })
    }

    // MARK: This phone

    /// The id the desktop knows this phone by.
    private var thisDeviceID: String? {
        if let id = Connection.shared.desktop?.deviceId, (try? YouAccessWire.deviceID(id)) != nil { return id }
        return devices.first(where: { $0.current })?.id
    }

    var unpairingThisPhone: Bool { busy.contains("thisPhone") }

    /// Unpair this phone. Its token ends at once, so on success the pairing is forgotten here and the phone goes back
    /// to sample data. Answers true when this phone is no longer paired.
    func unpairThisPhone() async -> Bool {
        followConnection()
        guard isLive, !busy.contains("thisPhone") else { return false }
        let account = liveAccount
        thisPhoneNotice = nil
        guard let id = thisDeviceID else {
            thisPhoneNotice = "This phone could not be found on your desktop. Unpair it in Kairos on your desktop, in Settings, Remote access."
            return false
        }
        busy.insert("thisPhone")
        defer { if liveAccount == account { busy.remove("thisPhone") } }
        do {
            try await liveClient().youAccessUnpair(id)
            Connection.shared.forgetPairing()
            return true
        } catch {
            if case .unauthorized? = error as? APIError {
                // The token already does not work: this phone is not paired any more.
                Connection.shared.forgetPairing()
                return true
            }
            guard stillLive(account) else { return false }
            if Self.isMissing(error) {
                // The token got through, so a 404 means the desktop did not find this id (or has no such route):
                // the pairing is forgotten here only if the desktop no longer knows this phone's token.
                do {
                    _ = try await liveClient().phoneSession()
                    guard stillLive(account) else { return false }
                    thisPhoneNotice = "Your desktop did not unpair this phone, and it is still paired. Unpair it in Kairos on your desktop, in Settings, Remote access."
                    return false
                } catch {
                    if case .unauthorized? = error as? APIError {
                        Connection.shared.forgetPairing()
                        return true
                    }
                    guard stillLive(account) else { return false }
                    thisPhoneNotice = "Your desktop did not unpair this phone. Check Paired phones in Kairos on your desktop, in Settings, Remote access."
                    return false
                }
            }
            if !(error is YouAccessNotSent) { Connection.shared.note(error) }
            if Self.wasRefused(error) {
                thisPhoneNotice = "This phone was not unpaired. " + Self.words(error)
                return false
            }
            // The answer was lost: ask the desktop whether this phone's token still works.
            do {
                _ = try await liveClient().phoneSession()
                guard stillLive(account) else { return false }
                thisPhoneNotice = "Your desktop did not confirm, and this phone is still paired. " + error.plainWords
                return false
            } catch {
                if case .unauthorized? = error as? APIError {
                    Connection.shared.forgetPairing()
                    return true
                }
                guard stillLive(account) else { return false }
                thisPhoneNotice = "Your desktop did not confirm, and it could not be checked. This phone may still be paired. Check Paired phones in Kairos on your desktop."
                return false
            }
        }
    }

    /// Turn a date into the short words the screens use.
    nonisolated static func day(_ date: Date?) -> String {
        guard let date = YouAccessWire.known(date) else { return "at a time not known" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    nonisolated static func ago(_ date: Date?) -> String {
        guard let date = YouAccessWire.known(date) else { return "not yet" }
        return date.formatted(.relative(presentation: .named))
    }
}

/// One quiet line on a You screen while paired: loading, what failed with a Try again, or where to do something.
struct YouAccessLine: View {
    let text: String
    var action: String? = nil
    var perform: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let action, let perform {
                Button {
                    Haptics.tap()
                    perform()
                } label: {
                    Text(action)
                        .font(KFont.ui(14, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.goldText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(minHeight: 48)
        .kCard(radius: 16)
    }
}

/// The loading note or the failure with Try again for one part; nothing once it is read.
struct YouAccessLoadLine: View {
    let part: YouAccessPart
    let loading: String
    private let live = YouAccessLive.shared

    var body: some View {
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

/// What a change that did not go through left behind, as one sentence.
struct YouAccessNoticeLine: View {
    let part: YouAccessPart
    private let live = YouAccessLive.shared

    var body: some View {
        if let text = live.notice[part] {
            NoteText(text: text, symbol: "exclamationmark.triangle")
        }
    }
}
