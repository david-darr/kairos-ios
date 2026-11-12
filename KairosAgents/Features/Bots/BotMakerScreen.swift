import SwiftUI

/// Make a new bot: ready-made bots and a blank start.
struct BotMakerScreen: View {
    var body: some View {
        BotsPage("Make a bot") { EmptyNote(text: "Coming next.") }
    }
}
