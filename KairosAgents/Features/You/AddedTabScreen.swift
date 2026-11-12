import SwiftUI

/// A tab the person added (a custom tab from the Tool Store). Starts as a plain page; the You team builds it.
struct AddedTabScreen: View {
    let title: String

    var body: some View {
        AreaView(title: title, symbol: "square.dashed", about: "")
    }
}
