import SwiftUI
import PDFKit

/// A read-only look at a file: a mini grid for sheets, questions for forms, text for documents, colour for images.
struct DrivePreviewView: View {
    let fileID: String
    @Environment(DriveUI.self) private var ui
    @Environment(\.dismiss) private var dismiss
    @State private var live: DriveLivePreview = .loading

    private var file: DriveFile? { ui.store.file(fileID) }

    var body: some View {
        ScrollView {
            if let file {
                VStack(alignment: .leading, spacing: 14) {
                    if ui.live {
                        liveContent(file).arrives(0)
                    } else {
                        content(file).arrives(0)
                    }
                    Label("Read-only preview. Open in Google to edit.", systemImage: "eye")
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .arrives(1)
                    editButton(file).arrives(2)
                    if ui.live { DriveLiveOpenLink(file: file).arrives(3) }
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
        .task(id: DriveStore.connectionKey) { await loadLive() }
    }

    // MARK: Paired desktop

    private func loadLive() async {
        guard ui.live, let file else { return }
        live = .loading
        do {
            switch file.kind {
            case .folder:
                live = .none
            case .sheet:
                let tabs = try await ui.store.sheetTabsLive(fileID)
                guard let first = tabs.first else {
                    live = .sheet(DriveSheetTab(title: "Sheet1", cells: []))
                    return
                }
                let cells = try await ui.store.cellsLive(fileID, tab: first, range: DriveCellRange(top: 0, left: 0, rows: 8, columns: 5))
                live = .sheet(DriveSheetTab(title: first, cells: cells.filter { row in row.contains { !$0.isEmpty } }))
            case .form:
                live = .form(DriveStore.liveForm(try await ui.store.formLive(fileID)))
            default:
                let read = try await ui.store.livePreview(fileID)
                if read.mime.hasPrefix("application/pdf"), let document = PDFDocument(data: read.data) {
                    live = .pdf(document)
                } else if read.mime.hasPrefix("image/"), let image = UIImage(data: read.data) {
                    live = .image(image)
                } else if read.mime.hasPrefix("text/html") {
                    live = .text(DriveWire.plainText(html: String(decoding: read.data, as: UTF8.self)))
                } else if read.mime.hasPrefix("text/") {
                    live = .text(String(decoding: read.data, as: UTF8.self))
                } else {
                    live = .cannot
                }
            }
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            if case .server(status: 415, _) = error as? APIError {
                live = .cannot
            } else if case .server(status: 413, _) = error as? APIError {
                live = .failed("This file is over the 25 MB a preview can be.", retry: false)
            } else {
                live = .failed("This preview could not be read. " + error.plainWords, retry: true)
            }
        }
    }

    @ViewBuilder
    private func liveContent(_ file: DriveFile) -> some View {
        switch live {
        case .loading:
            DriveLiveLine(text: "Reading \(file.name).")
        case .none:
            FilesEmpty(symbol: "folder", title: file.name, detail: "Folders open in the list.")
        case .cannot:
            DriveLiveLine(text: DriveWire.googleLink(file.webLink) == nil
                          ? "This file cannot be previewed on your phone."
                          : "This file cannot be previewed on your phone. Open it in Google instead.")
        case .failed(let why, let retry):
            if retry {
                DriveLiveLine(text: why, action: "Try again") { Task { await loadLive() } }
            } else {
                DriveLiveLine(text: why)
            }
        case .text(let text):
            DrivePaper {
                Text(text.isEmpty ? "This file has no text to show." : String(text.prefix(60_000)))
                    .font(KFont.ui(16))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        case .image(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .accessibilityLabel(file.name)
        case .pdf(let document):
            DrivePDFView(document: document)
                .frame(height: 520)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .accessibilityLabel(file.name)
        case .sheet(let tab):
            sheetPreview(Self.showing(file, sheet: tab, form: nil))
        case .form(let form):
            formPreview(Self.showing(file, sheet: nil, form: form))
        }
    }

    /// The file with what the desktop sent, for the sample's own sheet and form previews.
    private static func showing(_ file: DriveFile, sheet: DriveSheetTab?, form: DriveForm?) -> DriveFile {
        var shown = file
        if let sheet { shown.sheets = [sheet] }
        if let form { shown.form = form }
        return shown
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
                        Text(question.choices.isEmpty ? (question.label ?? question.type.title) : question.choices.joined(separator: " · "))
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

/// What the paired desktop sent for a preview.
enum DriveLivePreview {
    case loading
    case none
    case cannot
    case failed(String, retry: Bool)
    case text(String)
    case image(UIImage)
    case pdf(PDFDocument)
    case sheet(DriveSheetTab)
    case form(DriveForm)
}

/// A PDF from the desktop, read only.
struct DrivePDFView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}
