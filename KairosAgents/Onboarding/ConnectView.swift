import SwiftUI

/// Connect to your own desktop: its address and the pairing code from Kairos Settings.
/// The welcome shows this as its last step; "Look around first" keeps the sample data.
struct ConnectView: View {
    let back: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        PairingForm(
            back: back,
            skipTitle: "Look around first",
            onSkip: { app.finishOnboarding() },
            onPaired: { app.finishOnboarding() }
        )
    }
}

/// The pairing form itself, used by the welcome and by "Pair again" on the connection page.
struct PairingForm: View {
    let back: () -> Void
    var skipTitle: String? = nil
    var onSkip: () -> Void = {}
    let onPaired: () -> Void
    var connection: Connection = .shared
    /// Debug pictures open the form in a given state.
    var startAddress = ""
    var startCode = ""
    var startNote: String? = nil
    var startBusy = false

    @State private var address = ""
    @State private var code = ""
    @State private var note: String?
    @State private var noteIsGood = false
    @State private var busy = false
    @State private var prepared = false
    @FocusState private var field: Field?

    private enum Field { case address, code }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GlassIconButton(symbol: "chevron.left", label: "Back", action: back)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect your desktop")
                        .font(KFont.display(38))
                        .foregroundStyle(Palette.ink)
                    Text("The code is on your desktop: open Kairos, go to Settings, Remote access, and choose \"Pair the iPhone app\". It shows an address and a 6 digit code.")
                        .font(KFont.ui(16))
                        .foregroundStyle(Palette.inkDim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 26)

                VStack(spacing: 12) {
                    entry("Address", symbol: "link") {
                        TextField("desk.example.com", text: $address)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($field, equals: .address)
                            .submitLabel(.next)
                            .onSubmit { field = .code }
                            .accessibilityLabel("Desktop address")
                    }
                    entry("Pairing code", symbol: "number") {
                        TextField("6 digits", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($field, equals: .code)
                            .onChange(of: code) {
                                let digits = String(code.filter(\.isNumber).prefix(6))
                                if digits != code { code = digits }
                            }
                            .accessibilityLabel("Pairing code, 6 digits")
                    }
                }
                .font(KFont.ui(17))
                .foregroundStyle(Palette.ink)
                .padding(.top, 28)
                .disabled(busy)

                if let note {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: noteIsGood ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                        Text(note)
                            .font(KFont.ui(14.5, relativeTo: .subheadline))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(noteIsGood ? Palette.success : Palette.goldText)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button(action: connect) {
                    HStack(spacing: 10) {
                        if busy { ProgressView().tint(Palette.onGold) }
                        Text(busy ? "Pairing" : "Connect")
                            .font(KFont.ui(17, .semibold))
                    }
                    .foregroundStyle(Palette.onGold)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        LinearGradient(colors: [Palette.goldHi, Palette.goldDeep], startPoint: .top, endPoint: .bottom),
                        in: Capsule()
                    )
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
                    .opacity(busy ? 0.75 : 1)
                }
                .buttonStyle(PressStyle(scale: 0.97))
                .disabled(busy)
                .accessibilityLabel(busy ? "Pairing with your desktop" : "Connect")

                if let skipTitle {
                    QuietButton(title: skipTitle, action: onSkip)
                        .disabled(busy)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .animation(Motion.snappy, value: note)
        .animation(Motion.snappy, value: busy)
        .onAppear {
            guard !prepared else { return }
            prepared = true
            address = startAddress.isEmpty ? (connection.desktop?.host ?? "") : startAddress
            code = startCode
            note = startNote
            busy = startBusy
        }
    }

    private func connect() {
        field = nil
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty && code.isEmpty {
            show("Enter the address and the 6 digit code from your desktop.")
            return
        }
        if typed.isEmpty {
            show("Enter your desktop's address. Kairos shows it next to the code.")
            return
        }
        if APIClient.baseURL(from: typed) == nil {
            show(APIError.badAddress.plain)
            return
        }
        if code.count < 6 {
            show("The code has 6 digits. Check it on your desktop.")
            return
        }
        note = nil
        busy = true
        Task {
            do {
                try await connection.pair(address: typed, code: code)
                busy = false
                Haptics.success()
                let name = connection.desktop?.serverName ?? "Kairos"
                let who = connection.desktop?.username ?? ""
                noteIsGood = true
                note = who.isEmpty ? "Paired with \(name)." : "Paired with \(name) as \(who)."
                try? await Task.sleep(for: .seconds(0.7))
                onPaired()
            } catch {
                busy = false
                Haptics.thud()
                show(APIError.plain(error))
                if let failure = error as? APIError, case .server(let status, _) = failure, status == 400 || status == 429 {
                    code = ""
                    field = .code
                }
            }
        }
    }

    private func show(_ text: String) {
        noteIsGood = false
        note = text
    }

    private func entry<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.goldText).frame(width: 22)
                content()
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .kGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
