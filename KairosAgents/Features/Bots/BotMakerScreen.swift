import SwiftUI

/// Make a new bot: ready-made bots and a blank start.
/// Starts as a plain page; the Bots team builds the real screen here.
struct BotMakerScreen: View {
    var body: some View {
        AreaView(title: "Make a bot", symbol: "plus.circle", about: "Start from a ready-made bot or from scratch.")
    }
}
