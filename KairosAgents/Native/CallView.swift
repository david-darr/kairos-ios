import SwiftUI

/// The call screen: a night ground in every look, the bot's face, three round keys.
/// The call itself lives in `CallCenter` (CallKit), so minimizing keeps it running under the pill.
struct CallView: View {
    let bot: Bot
    @Environment(\.dismiss) private var dismiss
    private var calls = CallCenter.shared
    private var voice = CallSession.shared

    init(bot: Bot) {
        self.bot = bot
    }

    private var session: CallCenter.Session? {
        calls.session?.bot.id == bot.id ? calls.session : nil
    }

    /// Paired, the call has a real voice; its timer starts when the microphone is really listening.
    private var live: Bool { voice.isLive(session?.uuid) }

    private var openedAt: Date? { live ? voice.openedAt : session?.connectedAt }

    /// The bars follow the real level (the microphone, or the bot while it speaks) in a live call.
    private var barScale: CGFloat {
        guard live, !calls.muted else { return 1 }
        return 0.45 + CGFloat(min(1, voice.level)) * 1.1
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("KAIROS CALL").font(KFont.label).tracking(2.2)
                HStack {
                    Button { minimize() } label: {
                        Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Minimize the call")
                    Spacer()
                }
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
            LevelBars(color: Palette.cream.opacity(0.75), active: !calls.muted)
                .scaleEffect(x: 1, y: barScale)
                .animation(Motion.snappy, value: barScale)
                .padding(.top, 6)
            Group {
                if let connected = openedAt {
                    TimelineView(.periodic(from: connected, by: 1)) { context in
                        Text(calls.muted ? "Muted · " + timer(context.date, since: connected) : timer(context.date, since: connected))
                    }
                } else if live, let status = voice.status(botName: bot.name, muted: calls.muted) {
                    Text(status)
                } else {
                    Text("Calling…")
                }
            }
            .font(KFont.ui(16).monospacedDigit())
            .foregroundStyle(Palette.cream.opacity(0.7))
            .padding(.top, 10)
            if live {
                VStack(spacing: 6) {
                    if openedAt != nil, let status = voice.status(botName: bot.name, muted: calls.muted) {
                        Text(status)
                            .font(KFont.ui(14, relativeTo: .subheadline))
                            .foregroundStyle(Palette.cream.opacity(0.6))
                            .contentTransition(.opacity)
                            .animation(Motion.gentle, value: status)
                    }
                    if let line = voice.line {
                        Text(line)
                            .font(KFont.ui(14, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.cream.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(.top, 6)
            }

            Spacer()
            Spacer()

            HStack(spacing: 34) {
                callKey("speaker.wave.2.fill", "Speaker", on: calls.speaker) { calls.toggleSpeaker() }
                callKey(calls.muted ? "mic.slash.fill" : "mic.fill", calls.muted ? "Unmute" : "Mute", on: calls.muted) { calls.toggleMute() }
                VStack(spacing: 8) {
                    Button {
                        Haptics.thud()
                        calls.endCall()
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
        .onAppear {
            calls.screenVisible = true
            calls.startCall(with: bot, present: false)
        }
        .onDisappear { calls.screenVisible = false }
        .onChange(of: calls.session == nil) {
            // The call ended elsewhere (the Lock Screen, the island, the desktop): close the screen.
            if calls.session == nil { dismiss() }
        }
    }

    private func minimize() {
        Haptics.tap()
        calls.showingCall = false
        dismiss()
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

    private func timer(_ now: Date, since start: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The minimized call: a glass pill at the top with the bot's face, the timer, mute and hang up.
struct CallPill: View {
    let session: CallCenter.Session
    let open: () -> Void
    private var calls = CallCenter.shared

    init(session: CallCenter.Session, open: @escaping () -> Void) {
        self.session = session
        self.open = open
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    BotFace(bot: session.bot, size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.bot.name).font(KFont.ui(15, .semibold)).foregroundStyle(Palette.ink)
                        Group {
                            if let connected = session.connectedAt {
                                Text(connected, style: .timer)
                            } else {
                                Text("Calling…")
                            }
                        }
                        .font(KFont.ui(12.5).monospacedDigit())
                        .foregroundStyle(Palette.success)
                    }
                    LevelBars(color: Palette.success, active: !calls.muted).scaleEffect(0.8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Back to the call with \(session.bot.name)")

            Button {
                Haptics.tap()
                calls.toggleMute()
            } label: {
                Image(systemName: calls.muted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(calls.muted ? Palette.night : Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(calls.muted ? Palette.cream : Palette.ink.opacity(0.12), in: Circle())
            }
            .buttonStyle(PressStyle(scale: 0.9))
            .accessibilityLabel(calls.muted ? "Unmute" : "Mute")

            Button {
                Haptics.thud()
                calls.endCall()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Palette.hangUp, in: Circle())
            }
            .buttonStyle(PressStyle(scale: 0.9))
            .accessibilityLabel("End call")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 50)
        .kGlass(Capsule(), interactive: true)
    }
}
