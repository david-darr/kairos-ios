import SwiftUI

/// Edit a block of cells in a Google Sheet: pick a tab and a range, change cells, save. Paired, the cells are read
/// only: the desktop gives only shown values, so the phone cannot tell a formula from its result, and saving would
/// replace a formula with its value. The screen says to change cells in Google Sheets.
struct DriveSheetEditor: View {
    let fileID: String
    @Environment(DriveUI.self) private var ui
    @Environment(\.dismiss) private var dismiss

    @State private var tab = 0
    @State private var rangeText = "A1:F12"
    @State private var loaded: DriveCellRange?
    @State private var loadedText = ""
    @State private var loadedTab = 0
    @State private var grid: [[String]] = []
    @State private var problem: String?
    @State private var loadCount = 0
    @State private var started = false
    // Paired: the tabs, and a read on its way.
    @State private var liveTabs: [String] = []
    @State private var reading = false

    private static let maxRows = 20
    private static let maxColumns = 12

    private var file: DriveFile? { ui.store.file(fileID) }

    var body: some View {
        ScrollView {
            if let file {
                VStack(alignment: .leading, spacing: 16) {
                    if ui.live {
                        if liveTabs.count > 1 { tabs(titles: liveTabs) }
                    } else if file.sheets.count > 1 {
                        tabs(file)
                    }
                    rangeBar
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.circle")
                            .font(KFont.ui(14.5, relativeTo: .subheadline))
                            .foregroundStyle(Palette.danger)
                            .transition(.opacity)
                    }
                    if ui.live && reading && loaded == nil {
                        DriveLiveLine(text: "Reading the sheet.")
                    }
                    if let loaded { gridView(loaded) }
                    if ui.live {
                        HintLine(text: "Change cells in Google Sheets. Your phone cannot tell a formula from the value it shows, so it does not save cells.")
                    } else {
                        GoldButton(title: "Save cells", action: save)
                            .padding(.top, 4)
                            .disabled(reading)
                            .opacity(reading ? 0.6 : 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            } else {
                FilesEmpty(symbol: "tablecells", title: "This sheet is gone", detail: "It was deleted or moved out of this Drive.", action: "Go back") { dismiss() }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            FilesHeader(title: file?.name ?? "Sheet", subtitle: tabTitle, back: { dismiss() })
        }
        .kScreen()
        .animation(Motion.snappy, value: problem)
        .onAppear {
            guard !started else { return }
            started = true
            if ui.live {
                Task { await startLive() }
            } else {
                load()
            }
        }
        .onChange(of: tab) {
            load()
        }
    }

    private var tabTitle: String {
        if ui.live {
            guard tab < liveTabs.count else { return "Sheets editor" }
            return "Sheets editor · \(liveTabs[tab])"
        }
        guard let file, tab < file.sheets.count else { return "Sheets editor" }
        return "Sheets editor · \(file.sheets[tab].title)"
    }

    private func tabs(titles: [String]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                    FilterPill(title: title, symbol: "tablecells", on: tab == index) { tab = index }
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sheet tabs")
    }

    // MARK: Paired desktop

    private func startLive() async {
        reading = true
        do {
            liveTabs = try await ui.store.sheetTabsLive(fileID)
            reading = false
            load()
        } catch {
            reading = false
            if error is CancellationError { return }
            problem = "This sheet could not be read. " + error.plainWords
        }
    }

    private func loadLive(_ range: DriveCellRange) {
        guard tab < liveTabs.count else {
            problem = liveTabs.isEmpty ? "This sheet has no tabs to show." : "Choose a tab"
            return
        }
        let title = liveTabs[tab]
        let text = normalized(rangeText)
        let chosen = tab
        reading = true
        Task {
            defer { reading = false }
            do {
                let cells = try await ui.store.cellsLive(fileID, tab: title, range: range)
                guard chosen == tab, text == normalized(rangeText) else { return }
                grid = cells
                loaded = range
                loadedText = text
                loadedTab = chosen
                loadCount += 1
                problem = nil
                Haptics.select()
            } catch {
                if error is CancellationError { return }
                problem = "These cells could not be read. " + error.plainWords
            }
        }
    }

    // MARK: Tabs and range

    private func tabs(_ file: DriveFile) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(file.sheets.enumerated()), id: \.offset) { index, sheet in
                    FilterPill(title: sheet.title, symbol: "tablecells", on: tab == index) { tab = index }
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sheet tabs")
    }

    private var rangeBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Cell range")
            HStack(spacing: 10) {
                TextField("A1:F12", text: $rangeText)
                    .font(KFont.ui(17, .medium))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(load)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .kCard(radius: 14, raised: true)
                    .accessibilityLabel("Cell range")
                Button(action: load) {
                    Text("Load range")
                        .font(KFont.ui(15.5, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.goldText)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(Palette.gold.opacity(0.14), in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
            Text("Up to 20 rows and 12 columns at a time.")
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
        }
    }

    // MARK: Grid

    private func gridView(_ range: DriveCellRange) -> some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Color.clear.frame(width: 36, height: 28)
                    ForEach(0..<range.columns, id: \.self) { c in
                        Text(DriveCellRange.columnName(range.left + c))
                            .font(KFont.ui(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkFaint)
                            .frame(width: 112, height: 28)
                    }
                }
                ForEach(0..<range.rows, id: \.self) { r in
                    gridRow(r, range: range)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.visible)
        .id(loadCount)
    }

    private func gridRow(_ r: Int, range: DriveCellRange) -> some View {
        HStack(spacing: 4) {
            Text("\(range.top + r + 1)")
                .font(KFont.ui(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .frame(width: 36, height: 44)
            ForEach(0..<range.columns, id: \.self) { c in
                if ui.live {
                    Text(cell(r, c).wrappedValue)
                        .font(KFont.ui(15, r == 0 && range.top == 0 ? .semibold : .regular))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(width: 112, height: 44, alignment: .leading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                        .accessibilityLabel("Row \(range.top + r + 1) column \(range.left + c + 1)")
                        .accessibilityValue(cell(r, c).wrappedValue)
                } else {
                    TextField("", text: cell(r, c))
                        .font(KFont.ui(15, r == 0 && range.top == 0 ? .semibold : .regular))
                        .foregroundStyle(Palette.ink)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 10)
                        .frame(width: 112, height: 44)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                        .accessibilityLabel("Row \(range.top + r + 1) column \(range.left + c + 1)")
                }
            }
        }
    }

    /// A safe binding: it never reads outside the grid, even while a new range is loading.
    private func cell(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(
            get: { r < grid.count && c < grid[r].count ? grid[r][c] : "" },
            set: { value in
                if r < grid.count && c < grid[r].count { grid[r][c] = value }
            }
        )
    }

    // MARK: Load and save

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).uppercased()
    }

    private func load() {
        guard let range = DriveCellRange.parse(rangeText) else {
            problem = "Use a range such as A1:L20"
            return
        }
        guard range.rows <= Self.maxRows, range.columns <= Self.maxColumns else {
            problem = "Choose up to 20 rows and 12 columns"
            return
        }
        if ui.live {
            loadLive(range)
            return
        }
        grid = ui.store.cells(fileID, tab: tab, range: range)
        loaded = range
        loadedText = normalized(rangeText)
        loadedTab = tab
        loadCount += 1
        problem = nil
        Haptics.select()
    }

    private func save() {
        guard let range = loaded else {
            problem = "Load a range first"
            return
        }
        guard normalized(rangeText) == loadedText, loadedTab == tab else {
            problem = "Load the new range before saving"
            return
        }
        // Paired, cells are never saved from the phone (see the type's note); the button is not drawn.
        guard !ui.live else { return }
        ui.store.saveCells(fileID, tab: tab, range: range, values: grid)
        problem = nil
        Haptics.success()
        ui.toaster.say("Sheet saved")
    }
}
