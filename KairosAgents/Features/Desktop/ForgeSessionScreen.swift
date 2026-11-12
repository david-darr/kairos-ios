import SwiftUI

nonisolated enum ForgeSessionSheet: String, Identifiable, Hashable, Sendable {
    case actions, fullAccess, access, model, end, git, runApp, rename
    var id: String { rawValue }
}

/// One Forge session on the phone: the transcript with its work, inline approvals and per-turn review,
/// and a composer where Build or Plan, the model and the permission mode are always visible.
struct ForgeSessionScreen: View {
    let sessionID: String
    var start: ForgeSessionSheet? = nil

    @State private var store = ForgeStore.shared
    @State private var draft = ""
    @State private var sheet: ForgeSessionSheet?
    @State private var go: DesktopRoute?
    @State private var openFolds: Set<String> = []
    @State private var longOpen: Set<String> = []
    @State private var atBottom = true
    @State private var undoTurn: String?
    @State private var answering = false
    @State private var rea = false
    @State private var toast: String?
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss

    private var session: ForgeSessionInfo? { store.session(sessionID) }
    private var project: ForgeProject? { session.flatMap { store.project($0.projectID) } }
    private var busy: Bool { session?.state == .working }
    private var readOnly: Bool { session?.ended ?? true }

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                DeskEmptyNote(symbol: "questionmark.folder", title: "Session not found", text: "It may have been deleted on your PC.")
                    .frame(maxHeight: .infinity)
                    .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Session") }
                    .kScreen()
            }
        }
        .navigationDestination(item: $go) { route in DesktopRouteView(route: route) }
        .sheet(item: $sheet) { which in sheetView(which) }
        .confirmationDialog("Undo this turn?", isPresented: Binding(get: { undoTurn != nil }, set: { if !$0 { undoTurn = nil } }), titleVisibility: .visible) {
            Button("Undo turn", role: .destructive) {
                if let undoTurn { withAnimation(Motion.snappy) { store.setReview(sessionID, turn: undoTurn, .undone) } }
                undoTurn = nil
                toast = "Turn undone. Files are back as they were."
            }
        } message: {
            Text("Restores the files this turn changed. Later edits to the same files are checked first.")
        }
        .machineToast($toast)
        .onAppear {
            if let start { sheet = start }
            if let last = session?.turns.last { openFolds.insert(last.id) }
        }
    }

    // MARK: Layout

    private func content(_ session: ForgeSessionInfo) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if session.branch == nil {
                        NoteLine(text: ForgeLocation.inPlace.explain, symbol: "exclamationmark.triangle")
                            .padding(12).kCard(radius: 16)
                    }
                    if session.turns.isEmpty {
                        DeskEmptyNote(symbol: "text.bubble", title: "Nothing yet", text: "Describe the next step for this project.")
                    }
                    ForEach(session.turns) { turn in
                        turnView(turn, session: session).id(turn.id)
                    }
                    ForEach(Array(session.queued.enumerated()), id: \.offset) { _, text in
                        HStack(spacing: 8) {
                            Image(systemName: "clock").font(.system(size: 12, weight: .semibold))
                            Text("Queued: \(text)").lineLimit(2)
                        }
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkDim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 60
            } action: { _, bottom in
                atBottom = bottom
            }
            .overlay(alignment: .bottom) {
                if !atBottom {
                    Button {
                        withAnimation(Motion.snappy) { proxy.scrollTo("end", anchor: .bottom) }
                    } label: {
                        Label("Latest", systemImage: "arrow.down")
                            .font(KFont.ui(14, .medium))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .kGlass(Capsule(), interactive: true)
                    }
                    .buttonStyle(PressStyle())
                    .padding(.bottom, 8)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Jump to latest")
                }
            }
            .onChange(of: session.turns.count) {
                withAnimation(Motion.snappy) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .animation(Motion.snappy, value: atBottom)
        .safeAreaInset(edge: .top, spacing: 0) { header(session) }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer(session) }
        .kScreen(glowAt: UnitPoint(x: 0.5, y: -0.05))
    }

    private func header(_ session: ForgeSessionInfo) -> some View {
        VStack(spacing: 8) {
            ScreenHeader(title: session.title, subtitle: "\(project?.name ?? "") · \(session.placeLabel)") {
                NavigationLink(value: DesktopRoute.changes(sessionID)) {
                    HStack(spacing: 5) {
                        Image(systemName: "plusminus").font(.system(size: 12, weight: .bold))
                        Text("\(session.changes.count)").font(KFont.ui(15, .semibold)).monospacedDigit()
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle(scale: 0.92))
                .kGlass(Capsule(), interactive: true)
                .accessibilityLabel("Changes, \(session.changes.count) files")
                GlassIconButton(symbol: "ellipsis", label: "Session actions") { sheet = .actions }
            }
            let apps = store.apps
            if !apps.isEmpty || session.ended {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        if session.ended {
                            Label("Ended. Read only.", systemImage: "lock")
                                .font(KFont.ui(13.5, .medium)).foregroundStyle(Palette.inkDim)
                                .padding(.horizontal, 12).frame(height: 36).kGlass(Capsule())
                        }
                        ForEach(apps) { app in
                            Button { go = .preview(app.sessionID) } label: {
                                HStack(spacing: 7) {
                                    PulsingDot(color: Palette.success, size: 6)
                                    Text(app.sessionID == sessionID ? ":\(String(app.port)) Preview" : ":\(String(app.port)) \(app.title)")
                                        .font(KFont.ui(13.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .kGlass(Capsule(), interactive: true)
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Running app on port \(String(app.port)), \(app.title). Open preview")
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: Turns

    private func turnView(_ turn: ForgeTurn, session: ForgeSessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            promptBubble(turn)
            if turn.afterBackground {
                Label("After background work", systemImage: "clock.arrow.circlepath")
                    .font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
            }
            workFold(turn)
            if let ask = turn.ask { askCard(ask) }
            if !turn.reply.isEmpty {
                Text(turn.reply)
                    .font(KFont.ui(16))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                    .textSelection(.enabled)
            }
            if !turn.running && !turn.files.isEmpty && turn.review == .open && !readOnly {
                reviewBar(turn)
            } else if turn.review == .undone {
                Label("Undone", systemImage: "arrow.uturn.backward").font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
            }
        }
    }

    private func promptBubble(_ turn: ForgeTurn) -> some View {
        let long = turn.prompt.count > 140
        let open = longOpen.contains(turn.id)
        return VStack(alignment: .trailing, spacing: 4) {
            Text(turn.prompt)
                .font(KFont.ui(16))
                .foregroundStyle(Palette.onGold)
                .lineLimit(long && !open ? 3 : nil)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(LinearGradient(colors: [Palette.goldHi, Palette.gold], startPoint: .top, endPoint: .bottom),
                            in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 7, topTrailingRadius: 20, style: .continuous))
            if long {
                Button(open ? "Show less" : "Show more") {
                    withAnimation(Motion.snappy) { if open { longOpen.remove(turn.id) } else { longOpen.insert(turn.id) } }
                }
                .font(KFont.ui(13, .medium))
                .foregroundStyle(Palette.goldText)
                .frame(minHeight: 32)
            }
        }
        .frame(maxWidth: 310, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func workFold(_ turn: ForgeTurn) -> some View {
        let open = openFolds.contains(turn.id)
        let reads = turn.steps.filter { $0.kind == .read || $0.kind == .search }.count
        let edits = turn.steps.filter { $0.kind == .edit }.count
        let commands = turn.steps.filter { $0.kind == .command }.count
        var parts: [String] = []
        if reads > 0 { parts.append("\(reads) read") }
        if edits > 0 { parts.append(edits == 1 ? "1 edit" : "\(edits) edits") }
        if commands > 0 { parts.append(commands == 1 ? "1 command" : "\(commands) commands") }
        let counts = parts.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) { if open { openFolds.remove(turn.id) } else { openFolds.insert(turn.id) } }
            } label: {
                HStack(spacing: 8) {
                    if turn.running { PulsingDot(color: Palette.working, size: 7) } else {
                        Image(systemName: "checkmark.circle").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.success)
                    }
                    Text(turn.duration).font(KFont.ui(14, .medium)).foregroundStyle(Palette.ink)
                    Text(counts)
                        .font(KFont.ui(13)).foregroundStyle(Palette.inkFaint).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.inkFaint)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.99))
            .accessibilityLabel("\(turn.duration). \(open ? "Hide" : "Show") the work")
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(turn.steps) { step in stepRow(step) }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .kCard(radius: 18)
    }

    @ViewBuilder
    private func stepRow(_ step: ForgeStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: step.failed ? "xmark.octagon" : step.kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(step.failed ? Palette.danger : Palette.inkDim)
                    .frame(width: 18)
                Text(step.summary)
                    .font(step.kind == .command ? CodeFont.mono(12.5) : KFont.ui(14))
                    .foregroundStyle(step.failed ? Palette.danger : Palette.ink)
                    .lineLimit(2)
                if step.failed { Text("Failed").font(KFont.ui(12, .medium)).foregroundStyle(Palette.danger) }
            }
            if let output = step.output {
                Text(output)
                    .font(CodeFont.mono(12))
                    .foregroundStyle(Palette.inkDim)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.groundDeep.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if let file = step.file, let change = session?.changes.first(where: { $0.path == file }) {
                diffCard(change)
            }
        }
    }

    private func diffCard(_ change: FileChange) -> some View {
        Button { go = .diff(session: sessionID, path: change.path) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.goldText)
                    Text(change.name).font(KFont.ui(14, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    DiffCount(added: change.added, removed: change.removed, size: 12.5)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.inkFaint)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                if change.binary {
                    Text("Binary file").font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint).padding([.horizontal, .bottom], 12)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array((change.hunks.first?.lines ?? []).filter { $0.kind != .context }.prefix(6))) { line in
                            DiffLineView(line: line, numbers: false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding([.horizontal, .bottom], 8)
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .accessibilityLabel("\(change.name), \(change.added) added, \(change.removed) removed. Open the diff")
    }

    private func askCard(_ ask: PermissionAsk) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Palette.gold).frame(width: 8, height: 8)
                Text("Needs you").font(KFont.label).tracking(1.2).foregroundStyle(Palette.goldText)
            }
            Text(ask.title).font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
            HStack(spacing: 6) {
                Text(ask.tool).font(KFont.ui(13, .medium)).foregroundStyle(Palette.inkDim)
                Text(ask.target).font(CodeFont.mono(12.5)).foregroundStyle(Palette.ink).lineLimit(2)
            }
            HStack(spacing: 10) {
                Button { answer(false) } label: {
                    Text("Deny").font(KFont.ui(16, .semibold)).foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Palette.danger.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressStyle())
                Button { answer(true) } label: {
                    Text(answering ? "Sending..." : "Allow").font(KFont.ui(16, .semibold)).foregroundStyle(Palette.onGold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Palette.gold, in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
            .disabled(answering || readOnly)
        }
        .padding(16)
        .kCard(radius: 22, raised: true)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.gold.opacity(0.5), lineWidth: 1))
    }

    private func answer(_ allow: Bool) {
        answering = true
        Haptics.tap()
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(Motion.snappy) { store.answer(sessionID, allow: allow) }
            answering = false
            if allow { Haptics.success() }
        }
    }

    private func reviewBar(_ turn: ForgeTurn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("This turn changed \(turn.files.count) \(turn.files.count == 1 ? "file" : "files")").font(KFont.ui(14.5, .medium)).foregroundStyle(Palette.ink)
                DiffCount(added: turn.added, removed: turn.removed, size: 13)
            }
            HStack(spacing: 8) {
                DeskPillButton(title: "Review", symbol: "eye") { go = .changes(sessionID) }
                DeskPillButton(title: "Undo", symbol: "arrow.uturn.backward", tint: Palette.danger) { undoTurn = turn.id }
                    .disabled(busy)
                    .opacity(busy ? 0.4 : 1)
                DeskPillButton(title: "Keep", symbol: "checkmark", filled: true) {
                    withAnimation(Motion.snappy) { store.setReview(sessionID, turn: turn.id, .kept) }
                }
            }
        }
        .padding(14)
        .kCard(radius: 20)
    }

    // MARK: Composer

    private func composer(_ session: ForgeSessionInfo) -> some View {
        VStack(spacing: 8) {
            if let background = session.background {
                Button { go = .computer } label: {
                    HStack(spacing: 10) {
                        PulsingDot(color: Palette.working, size: 7)
                        Text(background).font(KFont.ui(14, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                        Spacer()
                        Text("Watch").font(KFont.ui(14, .medium)).foregroundStyle(Palette.goldText)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .kGlass(Capsule(), interactive: true)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Background task, \(background). Watch on Computer")
            }
            if session.mode == .plan {
                NoteLine(text: "Plan mode: nothing changes until you switch to Build.", symbol: "list.bullet.clipboard")
                    .padding(.horizontal, 6)
            }
            GlassEffectContainer(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            modeSwitch(session)
                            Button { sheet = .model } label: {
                                Chip(text: session.model, symbol: "sparkle")
                            }
                            .buttonStyle(PressStyle())
                            .disabled(readOnly)
                            .accessibilityLabel("Model, \(session.model), \(session.effort) effort. Change")
                            Button { sheet = .access } label: {
                                Chip(text: session.access.rawValue, symbol: session.access == .full ? "bolt.shield.fill" : "checkmark.shield")
                                    .foregroundStyle(session.access == .full ? Palette.danger : Palette.ink)
                            }
                            .buttonStyle(PressStyle())
                            .disabled(readOnly)
                            .accessibilityLabel("Permission mode, \(session.access.rawValue). Change")
                        }
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.hidden)
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField(readOnly ? "This session has ended" : "Ask, build, or describe a change", text: $draft, axis: .vertical)
                            .font(KFont.ui(16.5))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1...5)
                            .focused($typing)
                            .disabled(readOnly)
                            .padding(.vertical, 11)
                        if busy {
                            Button {
                                Haptics.thud()
                                withAnimation(Motion.snappy) { store.stop(sessionID) }
                            } label: {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                    .frame(width: 36, height: 36)
                                    .background(Palette.ink.opacity(0.12), in: Circle())
                                    .frame(width: 44, height: 46)
                            }
                            .buttonStyle(PressStyle(scale: 0.88))
                            .accessibilityLabel("Stop")
                        }
                        Button(action: send) {
                            Image(systemName: busy ? "text.append" : "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(hasText ? Palette.onGold : Palette.inkFaint)
                                .frame(width: 36, height: 36)
                                .background(hasText ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Circle())
                                .frame(width: 44, height: 46)
                        }
                        .buttonStyle(PressStyle(scale: 0.88))
                        .disabled(!hasText || readOnly)
                        .accessibilityLabel(busy ? "Queue message" : "Send")
                    }
                    Text("\(project?.path ?? "")\(session.branch.map { " · \($0)" } ?? " · In place")")
                        .font(CodeFont.mono(11))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .kGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(Motion.snappy, value: busy)
    }

    private var hasText: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func modeSwitch(_ session: ForgeSessionInfo) -> some View {
        HStack(spacing: 2) {
            ForEach(ForgeMode.allCases, id: \.self) { mode in
                let on = session.mode == mode
                Button {
                    Haptics.select()
                    withAnimation(Motion.snappy) { store.update(sessionID) { $0.mode = mode } }
                } label: {
                    Text(mode.rawValue)
                        .font(KFont.ui(13.5, on ? .semibold : .regular))
                        .foregroundStyle(on ? Palette.onGold : Palette.inkDim)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(on ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Color.clear), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Palette.ink.opacity(0.08), in: Capsule())
        .disabled(busy || readOnly)
        .opacity(busy ? 0.55 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Haptics.tap()
        draft = ""
        if busy { toast = "Queued. It runs when this turn ends." }
        withAnimation(Motion.bouncy) { store.send(text, to: sessionID) }
        if let last = store.session(sessionID)?.turns.last { openFolds.insert(last.id) }
    }

    // MARK: Sheets

    private func binding<T>(_ key: WritableKeyPath<ForgeSessionInfo, T>, _ fallback: T) -> Binding<T> {
        Binding(
            get: { store.session(sessionID)?[keyPath: key] ?? fallback },
            set: { value in store.update(sessionID) { $0[keyPath: key] = value } }
        )
    }

    @ViewBuilder
    private func sheetView(_ which: ForgeSessionSheet) -> some View {
        switch which {
        case .actions: actionsSheet
        case .access: ForgeAccessSheet(access: binding(\.access, .supervised))
        case .fullAccess: ForgeAccessSheet(access: binding(\.access, .supervised), startOnConfirm: true)
        case .model: ForgeModelSheet(agent: binding(\.agent, ""), model: binding(\.model, ""), effort: binding(\.effort, "Medium"), locked: true)
        case .end:
            if let session {
                ForgeEndSheet(session: session) { choice in
                    store.end(sessionID, choice)
                    if choice != .keepAndLeave {
                        toast = choice == .merge ? "Merged into main" : "Session ended"
                        Task {
                            try? await Task.sleep(for: .seconds(0.8))
                            dismiss()
                        }
                    }
                }
            }
        case .git:
            ForgeGitSheet(sessionID: sessionID) { path in open(.diff(session: sessionID, path: path)) }
        case .runApp:
            ForgeRunAppSheet { command in
                store.runApp(sessionID, command: command)
                toast = "Starting the app. Waiting for it to be ready."
            }
        case .rename:
            ForgeRenameSheet(title: session?.title ?? "") { name in store.update(sessionID) { $0.title = name } }
        }
    }

    private func open(_ route: DesktopRoute) {
        sheet = nil
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            go = route
        }
    }

    private func then(_ next: ForgeSessionSheet) {
        sheet = nil
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            sheet = next
        }
    }

    private var actionsSheet: some View {
        FittedSheet(estimate: 720) {
            VStack(alignment: .leading, spacing: 14) {
                DeskSheetTitle(text: session?.title ?? "Session", detail: session.map { "\(project?.name ?? "") · \($0.agent) · \($0.model)" })
                let app = store.apps(for: sessionID).first
                HStack(spacing: 10) {
                    actionTile(app == nil ? "play.fill" : "safari", app == nil ? "Run app" : "Preview :\(String(app?.port ?? 0))") {
                        if app == nil { then(.runApp) } else { open(.preview(sessionID)) }
                    }
                    actionTile("terminal", "Terminal") { open(.terminal(sessionID)) }
                    actionTile("folder", "Explorer") { open(.explorer(sessionID)) }
                }
                .disabled(readOnly)
                VStack(spacing: 0) {
                    actionRow("plusminus", "Changes", "\(session?.changes.count ?? 0) files from the session start") { open(.changes(sessionID)) }
                    actionRow("arrow.triangle.branch", "Git", "Commit, push, pull and merge back") { then(.git) }
                    actionRow("pencil", "Rename") { then(.rename) }
                    actionRow("plus.bubble", "New session", "In \(project?.name ?? "this project")") {
                        if let project = project { store.repoProjectID = project.id }
                        store.composeRequested = true
                        open(.forgeHome)
                    }
                    Toggle(isOn: $rea) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rea ? "REA on" : "REA tools").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                            Text("Your managed integration's tools for this session").font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
                        }
                    }
                    .tint(Palette.gold)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 58)
                    .disabled(busy || readOnly)
                }
                .kCard(radius: 20)
                if let session {
                    VStack(alignment: .leading, spacing: 6) {
                        NoteLine(text: session.mode.explain, symbol: session.mode == .build ? "hammer" : "list.bullet.clipboard")
                        NoteLine(text: "\(session.access.rawValue): \(session.access.explain)", symbol: "checkmark.shield")
                    }
                    .padding(.horizontal, 4)
                }
                Button { then(.end) } label: {
                    Text("End session")
                        .font(KFont.ui(16.5, .semibold))
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Palette.danger.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(busy || readOnly)
                .opacity(busy || readOnly ? 0.45 : 1)
                if busy {
                    NoteLine(text: "Stop the agent first to end the session.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func actionTile(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(Palette.goldText)
                Text(title).font(KFont.ui(14, .medium)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .kCard(radius: 20, raised: true)
        }
        .buttonStyle(PressStyle())
    }

    private func actionRow(_ symbol: String, _ title: String, _ detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CardRow(symbol: symbol, title: title, detail: detail)
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }
}

/// One diff line: old and new numbers, a marker and the text.
struct DiffLineView: View {
    let line: DiffLine
    var numbers = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if numbers {
                Text(line.old.map { String($0) } ?? "")
                    .frame(width: 30, alignment: .trailing)
                Text(line.new.map { String($0) } ?? "")
                    .frame(width: 30, alignment: .trailing)
            }
            Text(marker).frame(width: 18).foregroundStyle(color)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(CodeFont.mono(12))
        .foregroundStyle(Palette.inkFaint)
        .padding(.vertical, 2)
        .padding(.trailing, 6)
        .background(background)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.kind == .add ? "Added" : (line.kind == .remove ? "Removed" : "Unchanged")): \(line.text)")
    }

    private var marker: String {
        switch line.kind {
        case .add: "+"
        case .remove: "-"
        case .context: " "
        }
    }

    private var color: Color {
        switch line.kind {
        case .add: Palette.success
        case .remove: Palette.danger
        case .context: Palette.inkFaint
        }
    }

    private var background: Color {
        switch line.kind {
        case .add: Palette.success.opacity(0.14)
        case .remove: Palette.danger.opacity(0.14)
        case .context: Color.clear
        }
    }
}
