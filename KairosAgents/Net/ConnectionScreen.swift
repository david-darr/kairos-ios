import SwiftUI

/// The connection to the person's desktop: its state, the paired desktop, pair again, sign out.
/// Starts as a plain page; the Home and chats team builds the real screen here.
struct ConnectionScreen: View {
    var body: some View {
        AreaView(title: "Your desktop", symbol: "desktopcomputer", about: "Pair this iPhone with your Kairos desktop.")
    }
}
