import SwiftUI

/// A short glass message near the bottom of a Desktop screen. The tab bar's own toast is hidden
/// under a full-screen workspace, so these screens keep their own.
struct MachineToast: ViewModifier {
    @Binding var text: String?
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let text {
                Text(text)
                    .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .kGlass(Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
                    .onAppear { schedule() }
                    .id(text)
            }
        }
        .animation(Motion.snappy, value: text)
    }

    private func schedule() {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(2.4))
            if !Task.isCancelled { text = nil }
        }
    }
}

extension View {
    func machineToast(_ text: Binding<String?>) -> some View { modifier(MachineToast(text: text)) }
}

/// A search field in a quiet card.
struct MachineSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
            TextField(prompt, text: $text)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(width: 32, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .kCard(radius: 23)
    }
}

/// Download progress drawn as a row of dots, like the desktop phone layout.
struct DotProgress: View {
    let progress: Double
    var cells = 24

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<cells, id: \.self) { index in
                Circle()
                    .fill(Double(index) < progress * Double(cells) ? Palette.gold : Palette.ink.opacity(0.14))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(progress * 100)) percent")
    }
}
