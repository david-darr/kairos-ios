import SwiftUI

/// The Tasks section of Library. Starts as the sample list; the Library planner team builds the real one.
struct LibraryTasksSection: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(SampleData.library(.tasks).enumerated()), id: \.element.id) { index, entry in
                EntryRow(entry: entry)
                    .arrives(index)
            }
        }
    }
}
