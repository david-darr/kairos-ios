import SwiftUI

// Small shared pieces for the Files and Notes sections of Library.
// Everything here is built from the design system; nothing restyles it.

/// The full-screen places that open from the Files section.
enum FilesCover: Identifiable, Hashable {
    case vault(VaultStart)
    case chatDocuments
    case drive
    case uploads
    case document(String?)

    var id: String {
        switch self {
        case .vault(let start): "vault-\(start.id)"
        case .chatDocuments: "chat-documents"
        case .drive: "drive"
        case .uploads: "uploads"
        case .document(let id): "document-\(id ?? "new")"
        }
    }
}

/// Where the Vault opens: its Home, a note, or the Map.
enum VaultStart: Hashable {
    case home
    case note(String)
    case map
    case today

    var id: String {
        switch self {
        case .home: "home"
        case .note(let id): "note-\(id)"
        case .map: "map"
        case .today: "today"
        }
    }
}

// MARK: - Toasts inside covers

/// Full-screen covers sit above the tab bar, so they show their own short messages.
@Observable
final class FilesToaster {
    var text: String?
    private var task: Task<Void, Never>?

    func say(_ text: String) {
        task?.cancel()
        withAnimation(Motion.snappy) { self.text = text }
        task = Task {
            try? await Task.sleep(for: .seconds(2.4))
            if !Task.isCancelled { withAnimation(Motion.snappy) { self.text = nil } }
        }
    }
}

extension View {
    /// Draws the toaster's message as a glass pill near the bottom and puts the toaster in the environment.
    func filesToasts(_ toaster: FilesToaster) -> some View {
        overlay(alignment: .bottom) {
            if let text = toaster.text {
                ToastPill(text: text)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .environment(toaster)
    }
}

// MARK: - Header for pushed screens and covers

/// A floating header: a round back button, a title (and optional subtitle), and round buttons on the right.
struct FilesHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var backSymbol = "chevron.left"
    var backLabel = "Back"
    let back: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            GlassIconButton(symbol: backSymbol, label: backLabel, action: back)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(KFont.ui(19, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(KFont.ui(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { trailing }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background { HeaderFade() }
    }
}

extension FilesHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, backSymbol: String = "chevron.left", backLabel: String = "Back", back: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, backSymbol: backSymbol, backLabel: backLabel, back: back) { EmptyView() }
    }
}

// MARK: - Search field

/// A glass search capsule with a clear button.
struct FilesSearchField: View {
    @Binding var text: String
    var prompt = "Search"
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.inkFaint)
            TextField(prompt, text: $text)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button {
                    Haptics.tap()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Clear search")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 46)
        .kGlass(Capsule())
        .animation(Motion.snappy, value: text.isEmpty)
    }
}

// MARK: - Small marks

/// The extension of a file as a small tag ("PDF", "MD").
struct TypeBadge: View {
    let text: String
    var tint: Color = Palette.goldText

    var body: some View {
        Text(text.uppercased())
            .font(KFont.ui(10.5, .semibold, relativeTo: .caption2))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// A round check mark used for picking rows and finishing notes.
struct CheckCircle: View {
    let on: Bool
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(on ? Palette.gold : Palette.lineStrong, lineWidth: 1.6)
            if on {
                Circle().fill(Palette.gold)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(Palette.onGold)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.bouncy, value: on)
    }
}

/// A small on/off pill for filters ("Orphans", "Starred").
struct FilterPill: View {
    let title: String
    var symbol: String? = nil
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            withAnimation(Motion.snappy) { action() }
        } label: {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(KFont.ui(14, on ? .semibold : .regular, relativeTo: .footnote)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(on ? Palette.onGold : Palette.inkDim)
            .padding(.horizontal, 13)
            .frame(minHeight: 36)
            .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? .clear : Palette.line, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A square tile with an icon, used for actions in a row ("Pin", "Share").
struct ActionTile: View {
    let symbol: String
    let title: String
    var on = false
    var danger = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .symbolVariant(on ? .fill : .none)
                    .contentTransition(.symbolEffect(.replace))
                Text(title).font(KFont.ui(12.5, relativeTo: .caption)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(danger ? Palette.danger : (on ? Palette.goldText : Palette.ink))
            .frame(maxWidth: .infinity, minHeight: 64)
            .kCard(radius: 16, raised: on)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

/// A plain empty state: a title, one line, and an optional action.
struct FilesEmpty: View {
    let symbol: String
    let title: String
    let detail: String
    var action: String? = nil
    var perform: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 60, height: 60)
                .background(Palette.surfaceRaised, in: Circle())
                .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
            Text(title).font(KFont.ui(18, .semibold, relativeTo: .headline)).foregroundStyle(Palette.ink)
            Text(detail)
                .font(KFont.ui(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
                .multilineTextAlignment(.center)
            if let action {
                Button {
                    Haptics.tap()
                    perform()
                } label: {
                    Text(action)
                        .font(KFont.ui(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.goldText)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Palette.gold.opacity(0.14), in: Capsule())
                }
                .buttonStyle(PressStyle())
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }
}

/// A card section with a small capital label above it.
struct FilesGroup<Content: View>: View {
    let label: String
    var trailing: String? = nil
    var trailingAction: () -> Void = {}
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: label)
                if let trailing {
                    Button(trailing) {
                        Haptics.tap()
                        trailingAction()
                    }
                    .font(KFont.ui(14, .medium, relativeTo: .footnote))
                    .foregroundStyle(Palette.goldText)
                    .frame(minHeight: 32)
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 4)
            content
        }
    }
}

// MARK: - Dates

nonisolated enum FilesDates {
    /// "Today 6:23 PM", "Tomorrow 9:00 AM", "Wed 9:00 AM", "Oct 30".
    static func short(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday \(time)" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 99
        if abs(days) < 7 { return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Just now", "5m ago", "3h ago", "2d ago", then a short date.
    static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400))d ago" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func full(_ date: Date) -> String {
        date.formatted(date: .complete, time: .shortened)
    }
}
