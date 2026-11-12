import SwiftUI

// Temporary: pages still being built.
struct RoutinesScreen: View { let botID: String; var body: some View { BotsPage("Routines") { EmptyNote(text: "Coming next.") } } }
struct RoutineEditorScreen: View { let botID: String; let routineID: UUID?; var body: some View { BotsPage("Routine") { EmptyNote(text: "Coming next.") } } }
struct TriggerEditorScreen: View { let botID: String; let triggerID: UUID?; let webhook: Bool; var body: some View { BotsPage("Trigger") { EmptyNote(text: "Coming next.") } } }
struct AutomationCalendarScreen: View { let botID: String?; var body: some View { BotsPage("Calendar") { EmptyNote(text: "Coming next.") } } }
struct AutomationsScreen: View { var body: some View { BotsPage("Automations") { EmptyNote(text: "Coming next.") } } }
struct TeamScreen: View { let teamID: String; var body: some View { BotsPage("Team") { EmptyNote(text: "Coming next.") } } }
struct TeamReportScreen: View { let teamID: String; var body: some View { BotsPage("Team report") { EmptyNote(text: "Coming next.") } } }
struct TeamMapScreen: View { var body: some View { BotsPage("Team map") { EmptyNote(text: "Coming next.") } } }
struct RoomScreen: View { let roomID: String; var body: some View { BotsPage("Room") { EmptyNote(text: "Coming next.") } } }
struct DepartmentsScreen: View { var body: some View { BotsPage("Departments") { EmptyNote(text: "Coming next.") } } }
struct AllBotsScreen: View { var body: some View { BotsPage("All bots") { EmptyNote(text: "Coming next.") } } }
struct ReadyMadeScreen: View { var body: some View { BotsPage("Ready-made") { EmptyNote(text: "Coming next.") } } }
struct ArchivedBotsScreen: View { var body: some View { BotsPage("Archived") { EmptyNote(text: "Coming next.") } } }
struct PackagesScreen: View { var body: some View { BotsPage("Packages") { EmptyNote(text: "Coming next.") } } }
