import SwiftUI

/// The Files section of Library: the Vault first, then chat documents, Google Drive, uploads
/// and the documents saved to the Library.
struct LibraryFilesSection: View {
    @Environment(AppRouter.self) private var router
    @Environment(ChromeState.self) private var chrome
    @State private var cover: FilesCover?
    @State private var vault = VaultStore.shared
    @State private var documents = LibraryDocumentsStore.shared
    @State private var uploads = UploadsStore.shared
    @State private var chats = ChatDocsStore.shared
    @State private var drive = DriveStore.shared

    init(cover: FilesCover? = nil) {
        _cover = State(initialValue: cover)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            vaultCard.arrives(0)
            if !vault.recent.isEmpty { recentVault.arrives(1) }
            placesCard.arrives(2)
            documentsCard.arrives(3)
        }
        .padding(.top, 6)
        .onChange(of: chrome.addTick) {
            if router.tab == .library { cover = .document(nil) }
        }
        .fullScreenCover(item: $cover) { cover in
            Group {
                switch cover {
                case .vault(let start): VaultScreen(start: start)
                case .chatDocuments: ChatDocumentsScreen()
                case .drive: DriveScreen()
                case .uploads: UploadsScreen()
                case .document(let id): LibraryDocumentEditor(documentID: id)
                }
            }
            .environment(router)
            .environment(chrome)
        }
    }

    // MARK: Vault

    private var vaultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                Haptics.tap()
                cover = .vault(.home)
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vault").font(KFont.display(34)).foregroundStyle(Palette.ink)
                        Text("\(vault.notes.count) notes · \(vault.folders.count) folders")
                            .font(KFont.ui(14.5, relativeTo: .subheadline))
                            .foregroundStyle(Palette.inkDim)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    VaultMiniMap()
                        .frame(width: 112, height: 72)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .accessibilityLabel("Vault, \(vault.notes.count) notes. Explore your notes")
            HStack(spacing: 8) {
                vaultPill("Browse", symbol: "folder", filled: true) { cover = .vault(.home) }
                vaultPill("Map", symbol: "point.3.connected.trianglepath.dotted") { cover = .vault(.map) }
                vaultPill("Today", symbol: "calendar.badge.plus") { cover = .vault(.today) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 26, raised: true)
    }

    private func vaultPill(_ title: String, symbol: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: symbol)
                .font(KFont.ui(14.5, .medium, relativeTo: .subheadline))
                .foregroundStyle(filled ? Palette.onGold : Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(filled ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.09)), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private var recentVault: some View {
        FilesGroup(label: "Recent in the vault") {
            VStack(spacing: 0) {
                let notes = vault.recent.prefix(3).compactMap { vault.note($0) }
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                    Button {
                        Haptics.tap()
                        cover = .vault(.note(note.id))
                    } label: {
                        HStack(spacing: 12) {
                            TypeBadge(text: "MD")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(note.title).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                                Text("Vault · \(FilesDates.ago(note.edited))").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 54)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            if index < notes.count - 1 { Palette.line.frame(height: 1).padding(.leading, 16) }
                        }
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                }
            }
            .kCard(radius: 20)
        }
    }

    // MARK: Other places

    private var placesCard: some View {
        VStack(spacing: 0) {
            placeRow("Chat documents", detail: "\(chats.fileCount) files from chats", symbol: "bubble.left.and.text.bubble.right") { cover = .chatDocuments }
            placeRow("Google Drive", detail: driveDetail, symbol: "externaldrive") { cover = .drive }
            placeRow("Uploads", detail: uploads.files.count == 1 ? "1 file" : "\(uploads.files.count) files", symbol: "arrow.up.doc", last: true) { cover = .uploads }
        }
        .kCard(radius: 20)
    }

    private var driveDetail: String {
        guard let account = drive.currentAccount else { return "Not connected" }
        return account.broken ? "Reconnect needed" : "Connected · \(account.storage)"
    }

    private func placeRow(_ title: String, detail: String, symbol: String, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .frame(width: 44, height: 44)
                    .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(KFont.ui(16.5, .medium)).foregroundStyle(Palette.ink)
                    Text(detail).font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { Palette.line.frame(height: 1).padding(.leading, 72) }
            }
        }
        .buttonStyle(PressStyle(scale: 0.99))
    }

    // MARK: Documents

    private var documentsCard: some View {
        FilesGroup(label: "Documents", trailing: "New document") {
            cover = .document(nil)
        } content: {
            let docs = Array(documents.documents.prefix(4))
            if docs.isEmpty {
                FilesEmpty(symbol: "doc.text", title: "No documents yet", detail: "Notes and drafts saved to your Library show up here.", action: "Create a document") { cover = .document(nil) }
                    .kCard(radius: 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(docs.enumerated()), id: \.element.id) { index, doc in
                        Button {
                            Haptics.tap()
                            cover = .document(doc.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Palette.goldText)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(doc.title).font(KFont.ui(16)).foregroundStyle(Palette.ink).lineLimit(1)
                                    Text("Updated \(FilesDates.ago(doc.updated).lowercased())").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if index < docs.count - 1 { Palette.line.frame(height: 1).padding(.leading, 54) }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.99))
                    }
                    if documents.documents.count > docs.count {
                        Button {
                            Haptics.tap()
                            cover = .chatDocuments
                        } label: {
                            Text("All \(documents.documents.count) documents")
                                .font(KFont.ui(15, .medium, relativeTo: .subheadline))
                                .foregroundStyle(Palette.goldText)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(alignment: .top) { Palette.line.frame(height: 1) }
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .kCard(radius: 20)
            }
        }
    }
}

/// A small decorative map of links for the Vault card.
struct VaultMiniMap: View {
    private let points: [CGPoint] = [
        CGPoint(x: 0.12, y: 0.62), CGPoint(x: 0.3, y: 0.22), CGPoint(x: 0.48, y: 0.55),
        CGPoint(x: 0.66, y: 0.18), CGPoint(x: 0.86, y: 0.42), CGPoint(x: 0.7, y: 0.86), CGPoint(x: 0.36, y: 0.9),
    ]
    private let links: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 4), (2, 5), (2, 6), (0, 6), (4, 5)]

    var body: some View {
        Canvas { context, size in
            for (a, b) in links {
                var path = Path()
                path.move(to: CGPoint(x: points[a].x * size.width, y: points[a].y * size.height))
                path.addLine(to: CGPoint(x: points[b].x * size.width, y: points[b].y * size.height))
                context.stroke(path, with: .color(Palette.gold.opacity(0.45)), lineWidth: 1)
            }
            for index in points.indices {
                let r: CGFloat = index == 2 ? 5.5 : 3.5
                let p = CGPoint(x: points[index].x * size.width, y: points[index].y * size.height)
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(index == 2 ? Palette.gold : Palette.inkDim))
            }
        }
    }
}
