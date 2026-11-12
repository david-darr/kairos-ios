import SwiftUI

/// The Files section of Library. Starts as the sample list; the Library files team builds the real one.
struct LibraryFilesSection: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(SampleData.library(.files).enumerated()), id: \.element.id) { index, entry in
                EntryRow(entry: entry)
                    .arrives(index)
            }
        }
    }
}
