import SwiftUI
import UIKit

/// Files on the PC: places and projects first, then folders you can open one inside another.
struct PCFilesScreen: View {
    var path: String = ""
    var preview: String? = nil

    @State private var search = ""
    @State private var sort: PCSort = .name
    @State private var open: PCItem?
    @State private var toast: String?
    @State private var started = false

    private let files = PCFilesSample()

    private var title: String {
        path.isEmpty ? "Files on this PC" : (path.split(separator: "/").last.map(String.init) ?? path)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if path.isEmpty {
                    rootContent
                } else {
                    folderContent
                }
                NoteLine(text: "Changes to files happen on your PC. From here you can look, share and ask.", symbol: "desktopcomputer")
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: title, subtitle: files.displayPath(path)) {
                if !path.isEmpty {
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(PCSort.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 44, height: 44)
                            .kGlass(Circle(), interactive: true)
                    }
                    .accessibilityLabel("Sort by \(sort.rawValue.lowercased())")
                }
            }
        }
        .kScreen()
        .machineToast($toast)
        .sheet(item: $open) { item in
            PCFilePreview(item: item, text: files.text(of: item.path), place: files.displayPath(item.path)) { message in
                toast = message
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            if let preview, let item = files.items(in: path).first(where: { $0.path == preview }) { open = item }
        }
    }

    // MARK: Root

    private var rootContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Places")
                VStack(spacing: 0) {
                    ForEach(Array(PCFilesSample.places.enumerated()), id: \.element.id) { offset, place in
                        NavigationLink(value: DesktopRoute.pcFiles(place.path)) {
                            CardRow(
                                symbol: PCFilesSample.placeSymbols[place.name] ?? "folder",
                                title: place.name,
                                value: "\(files.count(in: place.path))",
                                last: offset == PCFilesSample.places.count - 1
                            )
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                        .accessibilityLabel("\(place.name), \(files.count(in: place.path)) items")
                    }
                }
                .kCard(radius: 22)
            }
            .arrives(0)

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Projects")
                VStack(spacing: 0) {
                    let projects = files.items(in: "Projects")
                    ForEach(Array(projects.enumerated()), id: \.element.id) { offset, project in
                        NavigationLink(value: DesktopRoute.pcFiles(project.path)) {
                            CardRow(symbol: "hammer", title: project.name, detail: files.displayPath(project.path), value: project.modified, last: offset == projects.count - 1)
                        }
                        .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .kCard(radius: 22)
            }
            .arrives(1)
        }
    }

    // MARK: Folder

    private var shown: [PCItem] {
        let all = files.items(in: path).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        let sorted: [PCItem]
        switch sort {
        case .name: sorted = all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date: sorted = all.sorted { $0.age > $1.age }
        case .size: sorted = all.sorted { $0.bytes > $1.bytes }
        }
        return sorted.filter { $0.kind == .folder } + sorted.filter { $0.kind != .folder }
    }

    private var folderContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            MachineSearchField(prompt: "Search this folder", text: $search)
            let items = shown
            if files.items(in: path).isEmpty {
                DeskEmptyNote(symbol: "folder", title: "Nothing here", text: "This folder is empty.")
                    .kCard(radius: 22)
            } else if items.isEmpty {
                NoteLine(text: "Nothing in this folder matches that.", symbol: "magnifyingglass")
            } else {
                HStack {
                    Text("\(items.count) items").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    Spacer()
                    Text("Sorted by \(sort.rawValue.lowercased())").font(KFont.ui(14, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        row(item, last: offset == items.count - 1)
                            .arrives(offset)
                    }
                }
                .kCard(radius: 22)
                .animation(Motion.snappy, value: sort)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: PCItem, last: Bool) -> some View {
        let detail = item.kind == .folder ? "\(files.count(in: item.path)) items · \(item.modified)" : "\(item.size) · \(item.modified)"
        if item.kind == .folder {
            NavigationLink(value: DesktopRoute.pcFiles(item.path)) {
                CardRow(symbol: item.symbol, title: item.name, detail: detail, last: last)
            }
            .buttonStyle(PressStyle(scale: 0.98))
        } else {
            Button {
                Haptics.tap()
                open = item
            } label: {
                CardRow(symbol: item.symbol, title: item.name, detail: detail, last: last)
            }
            .buttonStyle(PressStyle(scale: 0.98))
        }
    }
}

/// One file from the PC: a look at it, and what you can do with it from here.
struct PCFilePreview: View {
    let item: PCItem
    let text: String
    let place: String
    let say: (String) -> Void

    @State private var question = ""
    @State private var answer: String?
    @State private var asking = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 4) {
                    Text(item.name)
                        .font(KFont.ui(19, .semibold, relativeTo: .title3))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    Text("\(item.size) · \(item.modified)")
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 30)

                content

                actions

                askBox
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .kSheet()
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            ScrollView(.horizontal) {
                Text(text)
                    .font(CodeFont.mono(13))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .kCard(radius: 16)
        case .image:
            ZStack {
                LinearGradient(colors: [Color(hex: Palette.botPowder), Color(hex: Palette.botSand)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 0) {
                    Spacer()
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 60))
                        path.addLine(to: CGPoint(x: 70, y: 10))
                        path.addLine(to: CGPoint(x: 120, y: 45))
                        path.addLine(to: CGPoint(x: 170, y: 0))
                        path.addLine(to: CGPoint(x: 260, y: 60))
                        path.closeSubpath()
                    }
                    .fill(Color(hex: Palette.botSage))
                    .frame(width: 260, height: 60)
                }
                Circle().fill(Color(hex: Palette.botGold)).frame(width: 34, height: 34).offset(x: 70, y: -40)
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            .accessibilityLabel("A preview of \(item.name)")
        case .other, .folder:
            DeskEmptyNote(symbol: "doc", title: "No preview on the phone", text: "Open it on your PC to see it.")
                .kCard(radius: 16)
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            Button {
                say("Opened \(item.name) on your PC")
                dismiss()
            } label: {
                CardRow(symbol: "desktopcomputer", title: "Open on PC", detail: "In the app your PC uses for it", chevron: false)
            }
            .buttonStyle(PressStyle(scale: 0.98))

            ShareLink(item: item.kind == .text ? text : "\(item.name) on your PC: \(place)", subject: Text(item.name)) {
                CardRow(symbol: "square.and.arrow.up", title: "Send to phone", detail: item.kind == .text ? "Share the text" : "Share where it is", chevron: false)
            }
            .buttonStyle(PressStyle(scale: 0.98))

            Button {
                UIPasteboard.general.string = place
                Haptics.success()
                say("Path copied")
            } label: {
                CardRow(symbol: "doc.on.doc", title: "Copy path", detail: place, last: true, chevron: false)
            }
            .buttonStyle(PressStyle(scale: 0.98))
        }
        .kCard(radius: 20)
    }

    private var askBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Ask Kairos about it")
            HStack(spacing: 8) {
                TextField("What does this file say?", text: $question)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .submitLabel(.send)
                    .onSubmit(ask)
                Button(action: ask) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.onGold)
                        .frame(width: 34, height: 34)
                        .background(Palette.gold, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .accessibilityLabel("Ask")
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .kGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
            if asking {
                HStack(spacing: 8) {
                    PulsingDot(color: Palette.working, size: 6)
                    Text("Kairos is reading the file").font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkDim)
                }
            }
            if let answer {
                Text(answer)
                    .font(KFont.ui(15.5))
                    .foregroundStyle(Palette.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kCard(radius: 18, raised: true)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let asked = text.isEmpty ? "What is this file?" : text
        Haptics.tap()
        question = ""
        withAnimation(Motion.snappy) {
            asking = true
            answer = nil
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(Motion.bouncy) {
                asking = false
                answer = "You asked: \(asked) This is sample data. Connect your desktop and Kairos will read \(item.name) and answer for real."
            }
        }
    }
}
