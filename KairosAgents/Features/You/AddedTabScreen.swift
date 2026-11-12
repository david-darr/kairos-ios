import SwiftUI
import WebKit

/// A tab the person added from the Tool Store. The tab's own page is web content, so it is shown
/// in a web view; everything around it (header, menu, states) is native. No network loads.
struct AddedTabScreen: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var loading = true
    @State private var reloads = 0
    @State private var turnedOff = false
    @State private var confirmRemove = false
    @State private var showDetails = false
    private let store = StoreSample.shared

    private var item: StoreItem? { store.items.first { $0.kind == .tab && $0.name == title } }

    var body: some View {
        ZStack {
            if turnedOff {
                VStack(spacing: 12) {
                    Image(systemName: "power").font(.system(size: 30, weight: .medium)).foregroundStyle(Palette.goldText)
                        .frame(width: 72, height: 72).kGlass(Circle())
                    Text("\(title) is off").font(KFont.display(30)).foregroundStyle(Palette.ink)
                    Text("Turn it on to use it again.").font(KFont.ui(16)).foregroundStyle(Palette.inkDim)
                    PillButton(title: "Turn on", prominent: true) {
                        if let id = item?.id { store.update(id) { $0.on = true } }
                        withAnimation(Motion.snappy) { turnedOff = false }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabWebView(html: TabSamples.html(for: title, dark: scheme == .dark), reload: reloads) {
                    withAnimation(Motion.gentle) { loading = false }
                }
                .opacity(loading ? 0 : 1)
                .ignoresSafeArea(edges: .bottom)
                if loading {
                    VStack(spacing: 12) {
                        ProgressView().tint(Palette.gold)
                        Text("Opening \(title)").font(KFont.ui(15)).foregroundStyle(Palette.inkDim)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                GlassIconButton(symbol: "chevron.left", label: "Back") { dismiss() }
                Image(systemName: item?.symbol ?? "square.grid.2x2")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                Text(title).font(KFont.ui(20, .semibold, relativeTo: .title3)).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer()
                Menu {
                    Button("Reload", systemImage: "arrow.clockwise") {
                        loading = true
                        reloads += 1
                    }
                    if item != nil {
                        Button("Tab details", systemImage: "info.circle") { showDetails = true }
                    }
                    Button(turnedOff ? "Turn on" : "Turn off", systemImage: "power") {
                        if let id = item?.id { store.update(id) { $0.on = turnedOff } }
                        withAnimation(Motion.snappy) { turnedOff.toggle() }
                    }
                    Button("Remove from tabs", systemImage: "trash", role: .destructive) { confirmRemove = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .kGlass(Circle(), interactive: true)
                }
                .accessibilityLabel("Tab actions")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background { HeaderFade() }
        }
        .overlay(alignment: .bottom) { YouToastHost() }
        .kScreen()
        .confirmationDialog("Remove \(title) from your tabs?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let item { store.update(item.id) { $0.added = false } }
                YouStore.shared.say("\(title) removed. Add it again from the Tool Store.")
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(isPresented: $showDetails) {
            if let item { StoreItemScreen(itemID: item.id) }
        }
        .onChange(of: scheme) {
            loading = true
            reloads += 1
        }
        .youDestinations()
    }
}

/// The web view for a tab's own HTML. Transparent, so the ground shows behind it.
struct TabWebView: UIViewRepresentable {
    let html: String
    let reload: Int
    let loaded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(loaded: loaded) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.navigationDelegate = context.coordinator
        view.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastReload = reload
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.loaded = loaded
        if context.coordinator.lastReload != reload {
            context.coordinator.lastReload = reload
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: () -> Void
        var lastReload = 0

        init(loaded: @escaping () -> Void) { self.loaded = loaded }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded()
        }
    }
}

/// Small sample pages for the added tabs, in the Kairos colours for each look.
enum TabSamples {
    static func html(for title: String, dark: Bool) -> String {
        let body: String
        switch title {
        case "CRM": body = crm
        case "Team board": body = board
        default: body = generic(title)
        }
        return page(body, dark: dark)
    }

    private static func page(_ body: String, dark: Bool) -> String {
        let ink = dark ? "#F2E8D8" : "#3A2A20"
        let dim = dark ? "#C9BBA8" : "#6B5646"
        let card = dark ? "rgba(242,232,216,0.07)" : "rgba(251,246,238,0.85)"
        let line = dark ? "rgba(242,232,216,0.11)" : "rgba(184,137,59,0.3)"
        let gold = dark ? "#E2B154" : "#83601F"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        :root { --ink: \(ink); --dim: \(dim); --card: \(card); --line: \(line); --gold: \(gold); }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 8px 16px 120px; background: transparent; color: var(--ink);
               font: 16px -apple-system, system-ui, sans-serif; -webkit-text-size-adjust: 100%; }
        h2 { font-size: 13px; letter-spacing: 1.4px; text-transform: uppercase; color: var(--dim); margin: 22px 4px 8px; font-weight: 600; }
        .card { background: var(--card); border: 1px solid var(--line); border-radius: 20px; padding: 4px 0; }
        .row { display: flex; align-items: center; gap: 12px; padding: 12px 16px; border-bottom: 1px solid var(--line); }
        .row:last-child { border-bottom: 0; }
        .grow { flex: 1; min-width: 0; }
        .name { font-weight: 600; }
        .dim { color: var(--dim); font-size: 14px; }
        .pill { font-size: 12px; padding: 4px 10px; border-radius: 99px; border: 1px solid var(--line); color: var(--gold); white-space: nowrap; }
        .avatar { width: 38px; height: 38px; border-radius: 50%; display: grid; place-items: center; border: 2px solid var(--gold); font-weight: 600; }
        .stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
        .stat { background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 12px; }
        .stat b { display: block; font-size: 22px; }
        .cols { display: grid; grid-template-columns: repeat(3, minmax(150px, 1fr)); gap: 10px; overflow-x: auto; }
        .ticket { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 10px 12px; margin-bottom: 8px; font-size: 15px; }
        button { font: inherit; color: var(--ink); background: var(--card); border: 1px solid var(--line); border-radius: 99px; padding: 10px 16px; min-height: 44px; }
        </style></head><body>\(body)</body></html>
        """
    }

    private static let crm = """
    <div class="stats">
      <div class="stat"><b>14</b><span class="dim">People</span></div>
      <div class="stat"><b>5</b><span class="dim">Open deals</span></div>
      <div class="stat"><b>$8.2k</b><span class="dim">In play</span></div>
    </div>
    <h2>Deals</h2>
    <div class="card">
      <div class="row"><div class="avatar">R</div><div class="grow"><div class="name">Riverside cafe</div><div class="dim">Ten city bikes for staff</div></div><span class="pill">Proposal</span></div>
      <div class="row"><div class="avatar">H</div><div class="grow"><div class="name">Hill school</div><div class="dim">Spring tune-up day</div></div><span class="pill">Talking</span></div>
      <div class="row"><div class="avatar">M</div><div class="grow"><div class="name">Market club</div><div class="dim">Repair stand rental</div></div><span class="pill">Won</span></div>
    </div>
    <h2>Follow up this week</h2>
    <div class="card">
      <div class="row"><div class="grow"><div class="name">Call the cafe about delivery</div><div class="dim">Due Thursday</div></div><button onclick="this.textContent='Done'">Mark done</button></div>
      <div class="row"><div class="grow"><div class="name">Send the school a quote</div><div class="dim">Due Friday</div></div><button onclick="this.textContent='Done'">Mark done</button></div>
    </div>
    """

    private static let board = """
    <div class="cols">
      <div><h2>To do</h2>
        <div class="ticket">Order brake pads</div>
        <div class="ticket">New price tags</div></div>
      <div><h2>Doing</h2>
        <div class="ticket">Window display</div></div>
      <div><h2>Done</h2>
        <div class="ticket">Fix the till printer</div>
        <div class="ticket">Weekly report</div></div>
    </div>
    <h2>Team</h2>
    <div class="card">
      <div class="row"><div class="avatar">S</div><div class="grow"><div class="name">Sam</div><div class="dim">2 tasks</div></div></div>
      <div class="row"><div class="avatar">A</div><div class="grow"><div class="name">Alex</div><div class="dim">1 task</div></div></div>
    </div>
    """

    private static func generic(_ title: String) -> String {
        """
        <div class="card"><div class="row"><div class="grow"><div class="name">\(title)</div>
        <div class="dim">A tab you added from the Tool Store. Its page runs here, on your phone, with your desktop's data.</div></div></div></div>
        <h2>Recent</h2>
        <div class="card">
          <div class="row"><div class="grow"><div class="name">Build 14 passed its tests</div><div class="dim">Today</div></div><span class="pill">Passed</span></div>
          <div class="row"><div class="grow"><div class="name">Level two needs a playtest</div><div class="dim">Yesterday</div></div><span class="pill">Waiting</span></div>
        </div>
        """
    }
}
