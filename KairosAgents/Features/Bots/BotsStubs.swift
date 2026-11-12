import SwiftUI

// Temporary: pages still being built.
struct TeamScreen: View { let teamID: String; var body: some View { BotsPage("Team") { EmptyNote(text: "Coming next.") } } }
struct TeamReportScreen: View { let teamID: String; var body: some View { BotsPage("Team report") { EmptyNote(text: "Coming next.") } } }
struct TeamMapScreen: View { var body: some View { BotsPage("Team map") { EmptyNote(text: "Coming next.") } } }
struct RoomScreen: View { let roomID: String; var body: some View { BotsPage("Room") { EmptyNote(text: "Coming next.") } } }
struct DepartmentsScreen: View { var body: some View { BotsPage("Departments") { EmptyNote(text: "Coming next.") } } }
struct AllBotsScreen: View { var body: some View { BotsPage("All bots") { EmptyNote(text: "Coming next.") } } }
struct ReadyMadeScreen: View { var body: some View { BotsPage("Ready-made") { EmptyNote(text: "Coming next.") } } }
struct ArchivedBotsScreen: View { var body: some View { BotsPage("Archived") { EmptyNote(text: "Coming next.") } } }
struct PackagesScreen: View { var body: some View { BotsPage("Packages") { EmptyNote(text: "Coming next.") } } }
