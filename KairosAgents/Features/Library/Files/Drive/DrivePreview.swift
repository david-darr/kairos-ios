import SwiftUI

/// A read-only look at a file: a mini grid for sheets, questions for forms, text for documents, colour for images.
struct DrivePreviewView: View {
    let fileID: String
    @Environment(DriveUI.self) private var ui
    @Environment(\.dismiss) private var dismiss

    private var file: DriveFile? { ui.store.file(fileID) }

    var body: some View {
        ScrollView {
            if let file {
                VStack(alignment: .leading, spacing: 14) {
                    content(file).arrives(0)
                    Label("Read-only preview. Open in Google to edit.", systemImage: "eye")
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .arrives(1)
                    editButton(file).arrives(2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            } else {
                FilesEmpty(symbol: "doc", title: "This file is gone", detail: "It was deleted or moved out of this Drive.", action: "Go back") { dismiss() }
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .kScreen()
    }

    private var header: some View {
        FilesHeader(title: file?.name ?? "Preview", subtitle: file.map { $0.meta }, back: { dismiss() }) {
            if let file {
                ShareLink(item: file.name) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("Share the name")
                GlassIconButton(symbol: "info.circle", label: "Details") {
                    Haptics.tap()
                    ui.path.append(.details(file.id))
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ file: DriveFile) -> some View {
        switch file.kind {
        case .sheet: sheetPreview(file)
        case .form: formPreview(file)
        case .image: imagePreview(file)
        case .folder:
            FilesEmpty(symbol: "folder", title: file.name, detail: "Folders open in the list.")
        default: textPreview(file)
        }
    }

    // MARK: Kinds

    private func textPreview(_ file: DriveFile) -> some View {
        DrivePaper {
            Text(file.body.isEmpty ? "This file has no text to show." : file.body)
                .font(KFont.ui(16))
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }

    private func sheetPreview(_ file: DriveFile) -> some View {
        let cells = file.sheets.first?.cells ?? []
        let rows = min(cells.count, 8)
        let columns = min(cells.map { $0.count }.max() ?? 0, 5)
        return DrivePaper {
            VStack(alignment: .leading, spacing: 10) {
                Text(file.sheets.first?.title ?? "Sheet1")
                    .font(KFont.ui(13, .semibold, relativeTo: .footnote))
                    .opacity(0.6)
                if rows == 0 || columns == 0 {
                    Text("This sheet is empty.").font(KFont.ui(15))
                } else {
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<rows, id: \.self) { r in
                                HStack(spacing: 0) {
                                    ForEach(0..<columns, id: \.self) { c in
                                        Text(value(cells, r, c))
                                            .font(KFont.ui(13.5, r == 0 ? .semibold : .regular, relativeTo: .footnote))
                                            .lineLimit(1)
                                            .frame(width: 92, height: 32, alignment: .leading)
                                            .padding(.horizontal, 6)
                                            .overlay(Rectangle().stroke(Palette.night.opacity(0.12), lineWidth: 0.5))
                                    }
                                }
                                .background(r == 0 ? Palette.night.opacity(0.06) : Color.clear)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private func value(_ cells: [[String]], _ r: Int, _ c: Int) -> String {
        r < cells.count && c < cells[r].count ? cells[r][c] : ""
    }

    private func formPreview(_ file: DriveFile) -> some View {
        let form = file.form ?? DriveForm(title: file.name)
        return DrivePaper {
            VStack(alignment: .leading, spacing: 12) {
                Text(form.title).font(KFont.ui(20, .semibold))
                Text(form.published ? "Taking responses" : "Not published")
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .opacity(0.6)
                if form.questions.isEmpty {
                    Text("No questions yet.").font(KFont.ui(15))
                }
                ForEach(Array(form.questions.enumerated()), id: \.element.id) { index, question in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(index + 1). \(question.text)").font(KFont.ui(15.5, .medium))
                        Text(question.choices.isEmpty ? question.type.title : question.choices.joined(separator: " · "))
                            .font(KFont.ui(13.5, relativeTo: .footnote))
                            .opacity(0.65)
                    }
                }
            }
        }
    }

    private func imagePreview(_ file: DriveFile) -> some View {
        let tints: [(UInt32, UInt32)] = [(0x6B5442, 0x3C2E24), (0x4E6070, 0x2C3640), (0x6E5A3A, 0x3A2E1E), (0x5A4A5E, 0x2E2633)]
        let pick = tints[abs(file.name.count) % tints.count]
        return RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: pick.0), Color(hex: pick.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.cream.opacity(0.7))
            }
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            .accessibilityLabel(file.name)
    }

    // MARK: Edit

    @ViewBuilder
    private func editButton(_ file: DriveFile) -> some View {
        if !file.trashed && file.kind == .sheet {
            GoldButton(title: "Edit cells") {
                Haptics.tap()
                ui.path.append(.sheetEditor(file.id))
            }
        } else if !file.trashed && file.kind == .form {
            GoldButton(title: "Edit form") {
                Haptics.tap()
                ui.path.append(.formEditor(file.id))
            }
        }
    }
}
