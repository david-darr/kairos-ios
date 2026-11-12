import SwiftUI

/// Add a tab: your added tabs, prebuilt tabs to add, build your own, or install one.
struct AddTabScreen: View {
    @Bindable private var store = StoreSample.shared
    @State private var installing = false
    @State private var removing: StoreItem?

    private var tabs: [StoreItem] { store.items.filter { $0.kind == .tab } }

    var body: some View {
        SettingsPage("Add a tab", subtitle: "Tabs live in Jump to. Hold the tab bar to reach them, or drag one onto the bar.") {
            SettingsGroup("Your tabs") {
                let mine = tabs.filter { $0.added }
                if mine.isEmpty { EmptyRow(text: "No tabs added yet.") }
                ForEach(mine) { tab in
                    HStack(spacing: 10) {
                        NavigationLink(value: YouRoute.addedTab(tab.name)) {
                            HStack(spacing: 12) {
                                Image(systemName: tab.symbol)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Palette.goldText)
                                    .frame(width: 26)
                                RowLabel(title: tab.name, detail: tab.needsApproval ? "Waiting for your approval" : tab.summary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        if tab.needsApproval {
                            NavigationLink(value: YouRoute.storeItem(tab.id)) {
                                StatusPill(text: "Review", tone: .warn).frame(minHeight: 44)
                            }
                        } else {
                            Button {
                                removing = tab
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Palette.danger)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Remove \(tab.name)")
                        }
                    }
                    .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 4)
                }
            }

            SettingsGroup("Prebuilt") {
                let offered = tabs.filter { $0.prebuilt && !$0.added }
                if offered.isEmpty { EmptyRow(text: "Every prebuilt tab is added.") }
                ForEach(offered) { tab in
                    HStack(spacing: 10) {
                        Image(systemName: tab.symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.goldText).frame(width: 26)
                        RowLabel(title: tab.name, detail: tab.summary)
                        YouPillButton(title: "Add", prominent: true) {
                            withAnimation(Motion.snappy) { store.update(tab.id) { $0.added = true; $0.on = true } }
                            YouStore.shared.say("\(tab.name) added. It is in Jump to.")
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }
            }

            SettingsGroup("Make your own") {
                YouNavRow(title: "Build your own tab", detail: "Describe it, and Kairos builds it", symbol: "wand.and.stars", to: .buildTab)
                ActionRow(title: "Install a tab", detail: "From a .kairostab file or a GitHub folder", symbol: "tray.and.arrow.down") { installing = true }
                YouNavRow(title: "Tabs in the Tool Store", symbol: "bag", to: .toolStore)
            }
        }
        .sheet(isPresented: $installing) { StoreSheetView(which: .installTab) }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let tab = removing {
                    withAnimation(Motion.snappy) {
                        if tab.prebuilt { store.update(tab.id) { $0.added = false } } else { store.items.removeAll { $0.id == tab.id } }
                    }
                }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("You can add it again from the Tool Store.")
        }
        .youDestinations()
    }
}
