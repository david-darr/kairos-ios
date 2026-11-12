import SwiftUI

/// Search finds chats, bots and areas, and runs actions. It stands in for the desktop command palette.
struct SearchView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var typing: Bool

    private struct Hit: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let bot: Bot?
        let run: () -> Void
    }

    private var hits: [Hit] {
        var all: [Hit] = []
        all.append(Hit(id: "a-chat", title: "New chat", detail: "Action", symbol: "plus.bubble", bot: nil) { router.push(.newChat, on: .home) })
        all.append(Hit(id: "a-call", title: "Call Kip", detail: "Action", symbol: "phone", bot: nil) { router.push(.bot("kip"), on: .home) })
        for bot in SampleData.allBots {
            all.append(Hit(id: "b-\(bot.id)", title: bot.name, detail: bot.role, symbol: "", bot: bot) { router.push(.bot(bot.id), on: .home) })
        }
        for conversation in SampleData.conversations where conversation.kind == .model {
            all.append(Hit(id: conversation.id, title: conversation.title, detail: "Chat · \(conversation.time)", symbol: "sparkle", bot: nil) { router.open(conversation) })
        }
        for area in JumpArea.allCases {
            all.append(Hit(id: "j-\(area.rawValue)", title: area.title, detail: area.about, symbol: area.symbol, bot: nil) { router.open(area) })
        }
        if router.debugScreen == "bots" { return all.filter { $0.bot != nil }.reversed() }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(needle) || $0.detail.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.inkFaint)
                TextField("Search or do something", text: $query)
                    .font(KFont.ui(17))
                    .foregroundStyle(Palette.ink)
                    .focused($typing)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkFaint).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .frame(height: 50)
            .kCard(radius: 25, raised: true)
            .padding(.horizontal, 16)
            .padding(.top, 32)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(hits) { hit in
                        Button {
                            Haptics.select()
                            dismiss()
                            hit.run()
                        } label: {
                            HStack(spacing: 13) {
                                if let bot = hit.bot {
                                    BotFace(bot: bot, size: router.debugScreen == "bots" ? 78 : 50)
                                } else {
                                    Image(systemName: hit.symbol)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Palette.goldText)
                                        .frame(width: 40, height: 40)
                                        .background(Palette.ink.opacity(0.08), in: Circle())
                                        .frame(width: 50, height: 50)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(hit.title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                                    Text(hit.detail).font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                    }
                    if hits.isEmpty {
                        Text("Nothing matches \"\(query)\".")
                            .font(KFont.ui(15.5, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkFaint)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .kSheet()
        .onAppear { if router.debugScreen != "search" && router.debugScreen != "bots" { typing = true } }
    }
}
