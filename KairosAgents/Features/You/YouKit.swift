import SwiftUI
import UIKit

// The shared pieces every screen in You is built from: the routes, the sample store,
// the settings page and its grouped rows. Screens live in their own files.

// MARK: - Routes

/// Every screen you can reach inside You. Detail screens carry the id of what they show.
nonisolated enum YouRoute: Hashable, Sendable {
    case account, accounts, signIn
    case models, addModel, modelGuide
    case voice, botVoice
    case notifications, reachMe
    case channels, channel(String), addChannel(String), discord(String)
    case vault, phone
    case permissions, agentTools, computerUse, remote, forge
    case integrations, integration(String), addIntegration(String), mcpCatalog, google, images
    case look, layout
    case botPrefs, botKeys, botLogins, aboutYou, skillLibrary, botUsage, botHousekeeping, botTemplates, botComputers, connectedApps
    case users, logs, runs, sandbox, checkpoints, hooks, hook(String), editHook(String), system, shortcuts
    case help
    case toolStore, storeItem(String), addTab, addedTab(String), buildTab
    case connection
}

/// Where each route goes. One place, so every screen can link to any other with `NavigationLink(value:)`.
enum YouScreens {
    @ViewBuilder
    static func view(for route: YouRoute) -> some View {
        switch route {
        case .account: AccountScreen()
        case .accounts: DeviceAccountsScreen()
        case .signIn: SignInScreen()
        case .models: ModelsScreen()
        case .addModel: AddModelScreen()
        case .modelGuide: ModelGuideScreen()
        case .voice: VoiceScreen()
        case .botVoice: BotVoiceScreen()
        case .notifications: NotificationsRowDestination()
        case .reachMe: ReachMeScreen()
        case .channels: ChannelsScreen()
        case .channel(let id): ChannelDetailScreen(channelID: id)
        case .addChannel(let kind): AddChannelScreen(kind: kind)
        case .discord(let id): DiscordBotScreen(botID: id)
        case .vault: VaultSettingsScreen()
        case .phone: PhoneLineScreen()
        case .permissions: PermissionsScreen()
        case .agentTools: AgentToolsScreen()
        case .computerUse: ComputerUseScreen()
        case .remote: RemoteAccessScreen()
        case .forge: ForgeSettingsScreen()
        case .integrations: IntegrationsScreen()
        case .integration(let id): IntegrationDetailScreen(integrationID: id)
        case .addIntegration(let kind): AddIntegrationScreen(kind: kind)
        case .mcpCatalog: MCPCatalogScreen()
        case .google: GoogleScreen()
        case .images: ImageGenerationScreen()
        case .look: LookScreen()
        case .layout: LayoutScreen()
        case .botPrefs: BotPrefsScreen()
        case .botKeys: BotKeysScreen()
        case .botLogins: BotLoginsScreen()
        case .aboutYou: AboutYouScreen()
        case .skillLibrary: SkillLibraryScreen()
        case .botUsage: BotUsageScreen()
        case .botHousekeeping: BotHousekeepingScreen()
        case .botTemplates: BotTemplatesScreen()
        case .botComputers: BotComputersScreen()
        case .connectedApps: ConnectedAppsScreen()
        case .users: UsersScreen()
        case .logs: LogsScreen()
        case .runs: RunsScreen()
        case .sandbox: SandboxScreen()
        case .checkpoints: CheckpointsScreen()
        case .hooks: HooksScreen()
        case .hook(let id): HookDetailScreen(hookID: id)
        case .editHook(let id): HookEditScreen(hookID: id)
        case .system: SystemScreen()
        case .shortcuts: ShortcutsScreen()
        case .help: HelpScreen()
        case .toolStore: ToolStoreScreen()
        case .storeItem(let id): StoreItemScreen(itemID: id)
        case .addTab: AddTabScreen()
        case .addedTab(let id): AddedTabScreen(title: id)
        case .buildTab: BuildTabScreen()
        case .connection: ConnectionScreen()
        }
    }
}

extension View {
    /// Put on the root of a navigation stack that shows You screens.
    func youDestinations() -> some View {
        navigationDestination(for: YouRoute.self) { route in
            YouScreens.view(for: route)
        }
    }
}

// MARK: - The sample store

nonisolated struct DeviceAccount: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var colorHex: UInt32
    var isAdmin: Bool
    /// A PIN asked when someone switches into this account on this phone.
    var pin: String? = nil
    /// The sign-in ran out; switching asks for the password again.
    var expired = false
    var twoStep = false

    var initial: String { String(name.prefix(1)).uppercased() }
    var role: String { isAdmin ? "Admin" : "Member" }
}

/// What the You area knows on sample data. The desktop connection fills this in later.
@Observable
final class YouStore {
    static let shared = YouStore()

    /// The account colours the desktop offers.
    static let accountColors: [(name: String, hex: UInt32)] = [
        ("Gold", 0xD9B260), ("Powder", 0x8FB8D6), ("Sand", 0xE0A878),
        ("Rose", 0xD98A80), ("Sage", 0x8FB27E), ("Lilac", 0xB49ACF), ("Teal", 0x5FAFA8),
    ]

    var accounts: [DeviceAccount] = [
        DeviceAccount(id: "a-you", name: "Sam", colorHex: 0xD9B260, isAdmin: true, twoStep: true),
        DeviceAccount(id: "a-shop", name: "Bike shop", colorHex: 0x5FAFA8, isAdmin: false, pin: "2468"),
        DeviceAccount(id: "a-home", name: "Home", colorHex: 0xD98A80, isAdmin: false, expired: true),
    ]
    var currentID = "a-you"

    var current: DeviceAccount { accounts.first { $0.id == currentID } ?? accounts[0] }

    func update(_ change: (inout DeviceAccount) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.id == currentID }) else { return }
        change(&accounts[index])
    }

    func switchTo(_ id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        currentID = id
        say("Switched to \(current.name)")
    }

    func signOut(_ id: String) {
        guard accounts.count > 1 else { return }
        let name = accounts.first { $0.id == id }?.name ?? ""
        accounts.removeAll { $0.id == id }
        if currentID == id { currentID = accounts[0].id }
        say("Signed out of \(name)")
    }

    func addAccount(name: String) {
        let color = Self.accountColors[accounts.count % Self.accountColors.count].hex
        let account = DeviceAccount(id: "a-\(UUID().uuidString.prefix(6))", name: name, colorHex: color, isAdmin: false)
        accounts.append(account)
        currentID = account.id
        say("Signed in to \(name)")
    }

    /// Teams paused from Search ("pause the content team").
    var pausedTeams: Set<String> = []

    func toggleTeamPause(_ id: String) {
        if pausedTeams.contains(id) { pausedTeams.remove(id) } else { pausedTeams.insert(id) }
    }

    /// A screen to open when the You sheet next appears (Search uses this).
    var pendingRoute: YouRoute?

    // MARK: Short messages inside You

    var toast: String?
    private var toastTask: Task<Void, Never>?

    func say(_ text: String) {
        toastTask?.cancel()
        withAnimation(Motion.snappy) { toast = text }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            if !Task.isCancelled { withAnimation(Motion.snappy) { toast = nil } }
        }
    }
}

/// The short message pill, drawn at the bottom of every You screen.
struct YouToastHost: View {
    private let store = YouStore.shared

    var body: some View {
        ZStack {
            if let text = store.toast {
                ToastPill(text: text)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.snappy, value: store.toast)
        .allowsHitTesting(false)
    }
}

// MARK: - Avatar

/// An account's initial on its colour, with the colour as a ring.
struct AccountAvatar: View {
    let account: DeviceAccount
    var size: CGFloat = 44
    var ring: CGFloat? = nil

    var body: some View {
        Text(account.initial)
            .font(KFont.ui(size * 0.4, .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .background(Color(hex: account.colorHex).opacity(0.28), in: Circle())
            .background(Palette.surface2, in: Circle())
            .overlay(Circle().strokeBorder(Color(hex: account.colorHex), lineWidth: ring ?? max(2, size * 0.045)))
            .overlay(alignment: .bottomTrailing) {
                if account.pin != nil {
                    Image(systemName: "lock.fill")
                        .font(.system(size: max(8, size * 0.17), weight: .bold))
                        .foregroundStyle(Palette.onGold)
                        .frame(width: size * 0.34, height: size * 0.34)
                        .background(Palette.gold, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.ground, lineWidth: 1.5))
                        .offset(x: size * 0.04, y: size * 0.04)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - The page

/// A pushed settings page: a back button and title on top, then grouped content.
struct SettingsPage<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var trailing: Trailing
    var content: Content
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(KFont.ui(30, .semibold, relativeTo: .largeTitle))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(KFont.ui(15, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 4)
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 48)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                GlassIconButton(symbol: "chevron.left", label: "Back") { dismiss() }
                Spacer()
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background { HeaderFade() }
        }
        .overlay(alignment: .bottom) { YouToastHost() }
        .kScreen()
    }
}

extension SettingsPage where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Groups and rows

/// A grouped card of rows, like iOS Settings. Lines between rows are drawn for you.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionLabel(text: title).padding(.leading, 6) }
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(subviews) { subview in
                        subview
                        if subview.id != subviews.last?.id {
                            Palette.line.frame(height: 1).padding(.leading, 16)
                        }
                    }
                }
            }
            .kCard(radius: 22)
            if let footer {
                Text(footer)
                    .font(KFont.ui(13.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
    }
}

/// The left side of a row: an optional icon, a title and an optional line of detail.
struct RowLabel: View {
    let title: String
    var detail: String?
    var symbol: String?
    var tint: Color = Palette.goldText
    var titleColor: Color = Palette.ink

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KFont.ui(16))
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func rowFrame() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
    }
}

/// A row that opens another You screen.
struct YouNavRow: View {
    let title: String
    var detail: String?
    var symbol: String?
    var value: String?
    let to: YouRoute

    var body: some View {
        NavigationLink(value: to) {
            HStack(spacing: 8) {
                RowLabel(title: title, detail: detail, symbol: symbol)
                if let value {
                    Text(value).font(KFont.ui(15)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .rowFrame()
        }
        .buttonStyle(PressStyle(scale: 0.985))
    }
}

/// A row that does something when tapped. Gold for the good path, danger for removing things.
struct ActionRow: View {
    enum Tone { case normal, gold, danger }
    let title: String
    var detail: String?
    var symbol: String?
    var tone: Tone = .normal
    var trailing: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                RowLabel(title: title, detail: detail, symbol: symbol, tint: tint, titleColor: titleColor)
                if let trailing {
                    Text(trailing).font(KFont.ui(15)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
            }
            .rowFrame()
        }
        .buttonStyle(PressStyle(scale: 0.985))
    }

    private var tint: Color {
        switch tone {
        case .normal, .gold: Palette.goldText
        case .danger: Palette.danger
        }
    }

    private var titleColor: Color {
        switch tone {
        case .normal: Palette.ink
        case .gold: Palette.goldText
        case .danger: Palette.danger
        }
    }
}

/// A switch row. The switch changes at once.
struct YouToggleRow: View {
    let title: String
    var detail: String?
    var symbol: String?
    @Binding var isOn: Bool
    var disabled = false

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { value in
            Haptics.select()
            withAnimation(Motion.snappy) { isOn = value }
        })) {
            RowLabel(title: title, detail: detail, symbol: symbol)
        }
        .toggleStyle(.switch)
        .tint(Palette.gold)
        .disabled(disabled)
        .rowFrame()
    }
}

/// A row that only shows a value.
struct ValueRow: View {
    let title: String
    var detail: String?
    var symbol: String?
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            RowLabel(title: title, detail: detail, symbol: symbol)
            Text(value)
                .font(KFont.ui(15))
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .rowFrame()
        .accessibilityElement(children: .combine)
    }
}

/// A row with a pill on the right (Connected, Needs sign-in ...).
struct StatusRow: View {
    let title: String
    var detail: String?
    var symbol: String?
    let status: String
    var tone: StatusPill.Tone = .ok

    var body: some View {
        HStack(spacing: 8) {
            RowLabel(title: title, detail: detail, symbol: symbol)
            StatusPill(text: status, tone: tone)
        }
        .rowFrame()
        .accessibilityElement(children: .combine)
    }
}

/// A menu of choices shown in a row. The current choice sits on the right.
struct PickRow<Option: Hashable>: View {
    let title: String
    var detail: String?
    var symbol: String?
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String

    var body: some View {
        Menu {
            Picker(title, selection: Binding(get: { selection }, set: { value in
                Haptics.select()
                withAnimation(Motion.snappy) { selection = value }
            })) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
        } label: {
            HStack(spacing: 6) {
                RowLabel(title: title, detail: detail, symbol: symbol)
                Text(label(selection))
                    .font(KFont.ui(15))
                    .foregroundStyle(Palette.goldText)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .rowFrame()
        }
        .buttonStyle(PressStyle(scale: 0.985))
    }
}

/// A text entry row. Secure rows never show what was saved.
struct FieldRow: View {
    let title: String
    @Binding var text: String
    var prompt = ""
    var secure = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(KFont.ui(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
            Group {
                if secure {
                    SecureField(prompt, text: $text)
                } else {
                    TextField(prompt, text: $text)
                        .keyboardType(keyboard)
                }
            }
            .font(KFont.ui(16))
            .foregroundStyle(Palette.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
    }
}

/// A number with minus and plus.
struct YouStepperRow: View {
    let title: String
    var detail: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit = ""

    var body: some View {
        Stepper(value: Binding(get: { value }, set: { new in
            Haptics.select()
            value = new
        }), in: range, step: step) {
            HStack(spacing: 8) {
                RowLabel(title: title, detail: detail)
                Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                    .font(KFont.ui(15, .medium))
                    .foregroundStyle(Palette.goldText)
                    .contentTransition(.numericText())
                    .animation(Motion.snappy, value: value)
            }
        }
        .rowFrame()
    }
}

/// A slider with its value written beside the title.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let text: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                Spacer()
                Text(text(value)).font(KFont.ui(15)).foregroundStyle(Palette.goldText).monospacedDigit()
            }
            Slider(value: $value, in: range)
                .tint(Palette.gold)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// A short status word in a capsule.
struct StatusPill: View {
    enum Tone { case ok, warn, bad, muted, working }
    let text: String
    var tone: Tone = .ok

    var body: some View {
        Text(text)
            .font(KFont.ui(12.5, .medium, relativeTo: .caption))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var color: Color {
        switch tone {
        case .ok: Palette.success
        case .warn: Palette.goldText
        case .bad: Palette.danger
        case .muted: Palette.inkFaint
        case .working: Palette.working
        }
    }
}

/// A plain paragraph between groups, for an honest note or an explanation.
struct NoteText: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.goldText)
            }
            Text(text)
                .font(KFont.ui(14, relativeTo: .footnote))
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An empty list: a quiet line and, when there is one, the way to fill it.
struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(KFont.ui(15, relativeTo: .subheadline))
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
    }
}

/// A row of small text buttons at the bottom of a card (Test, Remove ...).
struct RowButtons<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small capsule button for inside rows.
struct YouPillButton: View {
    let title: String
    var symbol: String?
    var prominent = false
    var danger = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(KFont.ui(14, .medium, relativeTo: .footnote)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(prominent ? Palette.onGold : (danger ? Palette.danger : Palette.ink))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(prominent ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.1)), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// A search field at the top of a list.
struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.inkFaint)
            TextField(prompt, text: $text)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkFaint).frame(width: 40, height: 40)
                }
                .accessibilityLabel("Clear")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(height: 46)
        .kCard(radius: 23, raised: true)
    }
}

/// Small choice chips that scroll sideways (filters, categories).
struct YouChipPicker<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let on = item == selection
                    Button {
                        Haptics.select()
                        withAnimation(Motion.snappy) { selection = item }
                    } label: {
                        Text(title(item))
                            .font(KFont.ui(14, on ? .semibold : .regular, relativeTo: .footnote))
                            .foregroundStyle(on ? Palette.onGold : Palette.inkDim)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}
