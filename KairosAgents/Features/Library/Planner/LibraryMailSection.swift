import SwiftUI

/// The Mail section of Library. Starts as the sample list; the Library planner team builds the real one.
struct LibraryMailSection: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(SampleData.library(.mail).enumerated()), id: \.element.id) { index, entry in
                EntryRow(entry: entry)
                    .arrives(index)
            }
        }
    }
}
