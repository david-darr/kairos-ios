import SwiftUI

/// Connect to your own desktop: its address and the pairing code from Kairos Settings.
struct ConnectView: View {
    let back: () -> Void
    @Environment(AppModel.self) private var app
    @State private var address = ""
    @State private var code = ""
    @State private var note: String?
    @FocusState private var field: Field?

    private enum Field { case address, code }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassIconButton(symbol: "chevron.left", label: "Back", action: back)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("Connect your desktop")
                    .font(KFont.display(38))
                    .foregroundStyle(Palette.ink)
                Text("On your PC, open Kairos, then Settings, then Phone. It shows an address and a 6 digit code.")
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.inkDim)
                    .lineSpacing(3)
            }
            .padding(.top, 26)

            VStack(spacing: 12) {
                entry("Address", symbol: "link") {
                    TextField("yourname.kairos-agents.com", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($field, equals: .address)
                        .submitLabel(.next)
                        .onSubmit { field = .code }
                }
                entry("Pairing code", symbol: "number") {
                    TextField("6 digits", text: $code)
                        .keyboardType(.numberPad)
                        .focused($field, equals: .code)
                        .onChange(of: code) { code = String(code.filter(\.isNumber).prefix(6)) }
                }
            }
            .font(KFont.ui(17))
            .foregroundStyle(Palette.ink)
            .padding(.top, 28)

            if let note {
                Text(note)
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.goldText)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()

            VStack(spacing: 4) {
                GoldButton(title: "Connect") {
                    field = nil
                    withAnimation(Motion.snappy) {
                        if address.trimmingCharacters(in: .whitespaces).isEmpty || code.count < 6 {
                            note = "Enter the address and the 6 digit code from your PC."
                        } else {
                            note = "Pairing is not in this build yet. You can look around with sample data."
                        }
                    }
                }
                QuietButton(title: "Look around first") { app.finishOnboarding() }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .scrollDismissesKeyboard(.interactively)
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
