import SwiftUI

/// The Notes section of Library. Starts as the sample list; the Library files team builds the real one.
struct LibraryNotesSection: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(SampleData.library(.notes).enumerated()), id: \.element.id) { index, entry in
                EntryRow(entry: entry)
                    .arrives(index)
            }
        }
    }
}
