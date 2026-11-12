import SwiftUI

/// The call screen: a night ground in every look, the bot's face, three round keys.
struct CallView: View {
    let bot: Bot
    @Environment(\.dismiss) private var dismiss
    @State private var muted = false
    @State private var speaker = true
    @State private var started = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Minimize the call")
                Spacer()
                Text("KAIROS CALL").font(KFont.label).tracking(2.2)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Palette.cream.opacity(0.8))
            .padding(.horizontal, 12)

            Spacer()

            ZStack {
                Circle().fill(Color(hex: 0x1F3A40))
                Circle().strokeBorder(Palette.cream.opacity(0.22), lineWidth: 3)
                BotFace(bot: bot, size: 156, blinks: true, stage: Color(hex: 0x1F3A40))
            }
            .frame(width: 196, height: 196)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 18)

            Text(bot.name).font(KFont.display(44)).foregroundStyle(Palette.cream).padding(.top, 22)
            LevelBars(color: Palette.cream.opacity(0.75)).padding(.top, 6)
            TimelineView(.periodic(from: started, by: 1)) { context in
                Text(timer(context.date))
                    .font(KFont.ui(16).monospacedDigit())
                    .foregroundStyle(Palette.cream.opacity(0.7))
            }
            .padding(.top, 10)

            Spacer()
            Spacer()

            HStack(spacing: 34) {
                callKey("speaker.wave.2.fill", "Speaker", on: speaker) { speaker.toggle() }
                callKey(muted ? "mic.slash.fill" : "mic.fill", "Mute", on: muted) { muted.toggle() }
                VStack(spacing: 8) {
                    Button {
                        Haptics.thud()
                        dismiss()
                    } label: {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(Palette.hangUp, in: Circle())
                    }
                    .buttonStyle(PressStyle(scale: 0.9))
                    Text("End").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.cream.opacity(0.7))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("End call")
            }
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(colors: [Palette.callTop, Palette.callBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private func callKey(_ symbol: String, _ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) { action() }
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(on ? Color(hex: 0x2B2119) : Palette.cream)
                    .frame(width: 72, height: 72)
                    .background(on ? Palette.cream : Color(hex: 0x3E322A), in: Circle())
            }
            .buttonStyle(PressStyle(scale: 0.9))
            Text(title).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.cream.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func timer(_ now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(started)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
