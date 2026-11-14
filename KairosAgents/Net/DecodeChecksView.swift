import SwiftUI

/// Debug only: every bundled sample answer run through its real decoder, as a pass or fail list.
/// This stands in for unit tests, which this project has no target for.
struct DecodeChecksView: View {
    private struct Outcome: Identifiable {
        let id: String
        let passed: Bool
        let detail: String
    }

    @State private var outcomes: [Outcome] = []

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let failed = outcomes.filter { !$0.passed }
                HStack(spacing: 10) {
                    Image(systemName: failed.isEmpty ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(failed.isEmpty ? Palette.success : Palette.danger)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(outcomes.count - failed.count) of \(outcomes.count) pass")
                            .font(KFont.ui(20, .semibold, relativeTo: .title3))
                            .foregroundStyle(Palette.ink)
                        Text("Sample answers through the real decoders")
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
                .padding(.top, 6)

                ForEach(failed) { outcome in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(outcome.id, systemImage: "xmark.circle.fill")
                            .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Palette.danger)
                        Text(outcome.detail)
                            .font(KFont.ui(12.5, relativeTo: .caption))
                            .foregroundStyle(Palette.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .kCard(radius: 14, raised: true)
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(outcomes.filter(\.passed)) { outcome in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.success)
                                Text(outcome.id)
                                    .font(KFont.ui(12.5, .medium, relativeTo: .caption))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                            }
                            Text(outcome.detail)
                                .font(KFont.ui(11, relativeTo: .caption2))
                                .foregroundStyle(Palette.inkFaint)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .kCard(radius: 12)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .kScreen()
        .onAppear { if outcomes.isEmpty { outcomes = DecodeChecksView.runAll() } }
    }

    private static func runAll() -> [Outcome] {
        var result: [Outcome] = []
        for check in ChatSamples.checks + BotSamples.checks + VaultSamples.checks
            + NotesSamples.checks + TasksSamples.checks + CalendarSamples.checks + MailSamples.checks + CallSamples.checks
            + BotInboxSamples.checks + BotRoutineSamples.checks
            + BotSettingsSamples.checks + BotKnowledgeSamples.checks + BotRoomSamples.checks + BotTeamSamples.checks
            + DocsSamples.checks + DriveAPISamples.checks + SearchSamples.checks
            + YouAccessSamples.checks + MakeHomeSamples.checks + MakeDesignSamples.checks + DeskForgeSamples.checks
            + MakeVideoSamples.checks + YouVoiceSamples.checks + DeskChangesSamples.checks
            + DeskModelsSamples.checks + YouBotsSamples.checks + MakeStudioSamples.checks
            + DeskComputerSamples.checks + DeskFilesSamples.checks {
            do {
                result.append(Outcome(id: check.id, passed: true, detail: try check.run()))
            } catch {
                result.append(Outcome(id: check.id, passed: false, detail: String(describing: error)))
            }
        }
        result.append(addresses())
        result.append(backoff())
        return result
    }

    /// What a person types becomes one base address, or is refused.
    private static func addresses() -> Outcome {
        let good: [(String, String)] = [
            ("desk.example.com", "https://desk.example.com"),
            (" https://desk.example.com/ ", "https://desk.example.com"),
            ("desk.example.com:8422", "https://desk.example.com:8422"),
            ("HTTPS://Desk.Example.com", "HTTPS://Desk.Example.com"),
        ]
        for (typed, wanted) in good {
            guard APIClient.baseURL(from: typed)?.absoluteString == wanted else {
                return Outcome(id: "address", passed: false, detail: "\(typed) did not become \(wanted)")
            }
        }
        for typed in ["", "   ", "two words", "ftp://desk.example.com"] where APIClient.baseURL(from: typed) != nil {
            return Outcome(id: "address", passed: false, detail: "\"\(typed)\" should be refused")
        }
        let client = APIClient(base: URL(string: "https://desk.example.com")!, token: nil)
        let built = (try? client.url("/api/chat/artifacts", query: ["url": "/generated-files/a+b c.txt", "skip": nil]))?.absoluteString ?? ""
        guard built == "https://desk.example.com/api/chat/artifacts?url=/generated-files/a%2Bb%20c.txt" else {
            return Outcome(id: "address", passed: false, detail: "query built as \(built)")
        }
        return Outcome(id: "address", passed: true, detail: "4 typed forms, 4 refusals, 1 query")
    }

    private static func backoff() -> Outcome {
        let waits = (1...8).map { LiveEventStream.backoff($0) }
        let grows = waits[0] < 2 && waits[3] >= 8 && waits[7] <= 30.6
        return Outcome(id: "live.backoff", passed: grows, detail: grows ? "1 s up to 30 s" : "waits were \(waits)")
    }
}
