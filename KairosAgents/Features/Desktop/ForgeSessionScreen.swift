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
        // Paired with a desktop: that desktop's session, never a sample one.
        if DeskForgeLive.shared.on {
            DeskForgeSessionView(sessionID: sessionID)
        } else {
            sampleBody
        }
    }

    private var sampleBody: some View {
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
        .background { HeaderFade() }
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

// MARK: - Paired with a desktop

nonisolated enum DeskForgeSessionSheet: Identifiable, Hashable, Sendable {
    case actions, model, access, end, rename, git, runApp
    /// Undo one turn: the checkpoint's id and how many files it changed.
    case undo(String, Int)
    case mode(ForgeMode)

    var id: String {
        switch self {
        case .actions: return "actions"
        case .model: return "model"
        case .access: return "access"
        case .end: return "end"
        case .rename: return "rename"
        case .git: return "git"
        case .runApp: return "runApp"
        case .undo(let checkpoint, _): return "undo-" + checkpoint
        case .mode(let mode): return "mode-" + mode.rawValue
        }
    }
}

/// One Forge session on the paired desktop: its saved turns, the turn that is running, the requests it
/// waits on, and a composer. Everything shown was read from the desktop; nothing here is a sample.
///
/// Stays on the desktop: the terminal, Full access, the app's page, setting an app command, and "Keep"
/// (the desktop has no such state). A message typed while a turn runs is not queued on the phone.
struct DeskForgeSessionView: View {
    let sessionID: String

    @State private var live = DeskForgeLive.shared
    @State private var chat = ChatStore.shared
    @State private var draft = ""
    @State private var sheet: DeskForgeSessionSheet?
    @State private var go: DesktopRoute?
    @State private var toggledFolds: Set<String> = []
    @State private var longOpen: Set<String> = []
    @State private var atBottom = true
    @State private var notice: String?
    @State private var toast: String?
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss

    private var detail: DeskForgeDetail? { live.detail(sessionID) }
    private var project: DeskForgeProject? { detail.flatMap { live.project($0.projectID) } }
    private var running: Bool { live.isRunning(sessionID) }
    private var sending: Bool { live.isBusy("send:" + sessionID) }
    private var ended: Bool { detail?.ended ?? true }
    private var hasText: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// What the live stream last said about this session's turn. When it changes, the desktop is read at once.
    private var streamSignature: String {
        guard let run = chat.runs[sessionID] else { return "" }
        return "\(run.turnID)|\(run.status.rawValue)|\(run.request?.id ?? "")|\(run.stopping)|\(run.steps.count)"
    }

    var body: some View {
        Group {
            if let detail, live.isAdmin, detail.load == .loaded {
                content(detail)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    DeskForgeGate(load: detail?.load ?? .loading, reading: "Reading this session from your desktop.") {
                        Task { await live.loadSession(sessionID) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: live.session(sessionID)?.title ?? "Session") }
                .kScreen()
            }
        }
        .navigationDestination(item: $go) { route in DesktopRouteView(route: route) }
        .sheet(item: $sheet) { which in sheetView(which) }
        .machineToast($toast)
        .task(id: DeskForgeLive.connectionKey + "|" + sessionID) {
            guard live.on else { return }
            await live.loadSession(sessionID)
            if draft.isEmpty, let kept = live.takeDraft(sessionID) { draft = kept }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(live.isRunning(sessionID) ? 2 : 6))
                if Task.isCancelled { break }
                await live.pollSession(sessionID)
            }
        }
        .onChange(of: streamSignature) {
            Task { await live.pollSession(sessionID) }
        }
    }

    // MARK: Layout

    private func content(_ detail: DeskForgeDetail) -> some View {
        let turns = live.transcript(sessionID)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if detail.branch == nil {
                        NoteLine(text: ForgeLocation.inPlace.explain, symbol: "exclamationmark.triangle")
                            .padding(12).kCard(radius: 16)
                    }
                    if detail.skippedMessages > 0 {
                        HintLine(text: "\(detail.skippedMessages) messages could not be read and are not shown.")
                    }
                    if turns.isEmpty {
                        DeskEmptyNote(symbol: "text.bubble", title: "Nothing yet", text: "Describe the next step for this project.")
                    }
                    ForEach(turns) { turn in
                        turnView(turn, detail: detail).id(turn.id)
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
            .onChange(of: turns.count) {
                withAnimation(Motion.snappy) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .animation(Motion.snappy, value: atBottom)
        .safeAreaInset(edge: .top, spacing: 0) { header(detail) }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer(detail) }
        .kScreen(glowAt: UnitPoint(x: 0.5, y: -0.05))
    }

    private func header(_ detail: DeskForgeDetail) -> some View {
        VStack(spacing: 8) {
            ScreenHeader(title: detail.title.isEmpty ? "Session" : detail.title,
                         subtitle: "\(project?.name ?? "Forge") · \(detail.branch ?? "In place")") {
                NavigationLink(value: DesktopRoute.changes(sessionID)) {
                    Image(systemName: "plusminus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle(scale: 0.92))
                .kGlass(Circle(), interactive: true)
                .accessibilityLabel("Changes")
                GlassIconButton(symbol: "ellipsis", label: "Session actions") { sheet = .actions }
            }
            let app = live.app(for: sessionID)
            if detail.ended || app != nil {
                HStack(spacing: 8) {
                    if detail.ended {
                        Label("Ended. Read only.", systemImage: "lock")
                            .font(KFont.ui(13.5, .medium)).foregroundStyle(Palette.inkDim)
                            .padding(.horizontal, 12).frame(height: 36).kGlass(Capsule())
                    }
                    if let app {
                        // The app's page opens on the desktop only: this says it runs, and does not open.
                        HStack(spacing: 7) {
                            PulsingDot(color: Palette.success, size: 6)
                            Text(app.ready ? "App running on :\(String(app.port))" : "App starting on :\(String(app.port))")
                                .font(KFont.ui(13.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .kGlass(Capsule())
                        .accessibilityElement(children: .combine)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
        }
        .background { HeaderFade() }
    }

    // MARK: Turns

    private func turnView(_ turn: DeskForgeTurn, detail: DeskForgeDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !turn.prompt.isEmpty { promptBubble(turn) }
            if turn.afterBackground {
                Label("After background work", systemImage: "clock.arrow.circlepath")
                    .font(KFont.ui(12.5)).foregroundStyle(Palette.inkFaint)
            }
            if turn.live != nil || turn.runID != nil { workFold(turn, detail: detail) }
            if let request = turn.live?.request { requestCard(request) }
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
            if let failure = turn.failure {
                HintLine(text: failure, symbol: "exclamationmark.triangle", color: Palette.goldText)
            }
            reviewBar(turn, detail: detail)
        }
    }

    private func promptBubble(_ turn: DeskForgeTurn) -> some View {
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

    /// The steps to draw for a turn: the running turn's own, else a saved run's once it was read.
    private func shownSteps(of turn: DeskForgeTurn, detail: DeskForgeDetail) -> [DeskForgeStep]? {
        if let run = turn.live, !run.steps.isEmpty || run.running { return run.steps }
        guard let runID = turn.runID else { return turn.live?.steps }
        return detail.steps[runID]
    }

    private func workFold(_ turn: DeskForgeTurn, detail: DeskForgeDetail) -> some View {
        let isRunning = turn.live?.running == true
        // A running turn's work is open until it is folded; a finished turn's is folded until it is opened.
        let open = toggledFolds.contains(turn.id) != isRunning
        let steps = shownSteps(of: turn, detail: detail)
        let reads = (steps ?? []).filter { $0.kind == "read" || $0.kind == "search" }.count
        let edits = (steps ?? []).filter { $0.kind == "edit" }.count
        let commands = (steps ?? []).filter { $0.kind == "command" }.count
        var parts: [String] = []
        if reads > 0 { parts.append("\(reads) read") }
        if edits > 0 { parts.append(edits == 1 ? "1 edit" : "\(edits) edits") }
        if commands > 0 { parts.append(commands == 1 ? "1 command" : "\(commands) commands") }
        let counts = steps == nil ? "Show the work" : parts.joined(separator: ", ")
        let label: String
        if turn.live?.stopping == true {
            label = "Stopping"
        } else if isRunning {
            label = turn.live?.request != nil ? "Waiting for you" : "Working"
        } else {
            label = "Worked"
        }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) {
                    if toggledFolds.contains(turn.id) { toggledFolds.remove(turn.id) } else { toggledFolds.insert(turn.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    if isRunning { PulsingDot(color: Palette.working, size: 7) } else {
                        Image(systemName: "checkmark.circle").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.success)
                    }
                    Text(label).font(KFont.ui(14, .medium)).foregroundStyle(Palette.ink)
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
            .accessibilityLabel("\(label). \(open ? "Hide" : "Show") the work")
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    if let steps {
                        if steps.isEmpty {
                            Text(isRunning ? "No tools used yet." : "No tools were used.")
                                .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                        }
                        ForEach(steps) { step in stepRow(step) }
                    } else if let runID = turn.runID, detail.stepsUnread.contains(runID) {
                        Text("The steps could not be read from your desktop.")
                            .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    } else {
                        Text("Reading the steps.")
                            .font(KFont.ui(13.5, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.opacity)
                .task(id: turn.runID ?? "") {
                    // A saved turn's steps are read once, when its work is opened.
                    if steps == nil, let runID = turn.runID { await live.loadSteps(sessionID, runID: runID) }
                }
            }
        }
        .kCard(radius: 18)
    }

    private func stepRow(_ step: DeskForgeStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: step.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(step.failed ? Palette.danger : Palette.inkDim)
                    .frame(width: 18)
                Text(step.summary.isEmpty ? "Using \(step.name.isEmpty ? "a tool" : step.name)" : step.summary)
                    .font(step.kind == "command" ? CodeFont.mono(12.5) : KFont.ui(14))
                    .foregroundStyle(step.failed ? Palette.danger : Palette.ink)
                    .lineLimit(3)
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
        }
    }

    /// A request the agent waits on, as the desktop sent it. The phone answers once: allow, or deny.
    private func requestCard(_ request: ChatPermissionDTO) -> some View {
        let requestID = request.id ?? ""
        let answering = live.isBusy("answer:" + requestID)
        let unsettled = live.isUnsettled(requestID)
        let allow = DeskForgeLive.onceChoice(request, allow: true)
        let deny = DeskForgeLive.onceChoice(request, allow: false)
        let standing = (request.choices ?? []).contains { ($0.scope ?? "once") != "once" }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Palette.gold).frame(width: 8, height: 8)
                Text("Needs you").font(KFont.label).tracking(1.2).foregroundStyle(Palette.goldText)
            }
            if request.kind == "question" {
                Text("The agent asked you a question.").font(KFont.ui(17, .semibold)).foregroundStyle(Palette.ink)
                ForEach(Array((request.questions ?? []).enumerated()), id: \.offset) { _, question in
                    Text(question.question ?? "")
                        .font(KFont.ui(14.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HintLine(text: "Answer it in Kairos on your desktop.")
            } else {
                DeskForgeRequestText(request: request)
                if unsettled {
                    HintLine(text: "Not confirmed yet. Reading your desktop.", symbol: "clock")
                }
                HStack(spacing: 10) {
                    if deny != nil {
                        Button { answer(request, allow: false) } label: {
                            Text("Deny").font(KFont.ui(16, .semibold)).foregroundStyle(Palette.danger)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Palette.danger.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                    if allow != nil {
                        Button { answer(request, allow: true) } label: {
                            Text(answering ? "Sending..." : "Allow once").font(KFont.ui(16, .semibold)).foregroundStyle(Palette.onGold)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Palette.gold, in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .disabled(answering || unsettled || ended)
                .opacity(answering || unsettled ? 0.55 : 1)
                if allow == nil {
                    HintLine(text: "Allow this one in Kairos on your desktop.")
                } else if standing {
                    HintLine(text: "To always allow it, answer in Kairos on your desktop.")
                }
            }
        }
        .padding(16)
        .kCard(radius: 22, raised: true)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.gold.opacity(0.5), lineWidth: 1))
    }

    private func answer(_ request: ChatPermissionDTO, allow: Bool) {
        Haptics.tap()
        Task {
            let outcome = await live.answer(request, allow: allow, in: sessionID)
            if let line = outcome.line {
                notice = line
            } else if allow, outcome == .done {
                Haptics.success()
            }
        }
    }

    /// What a finished turn changed, with Undo. There is no Keep while paired: the desktop has no such state.
    @ViewBuilder
    private func reviewBar(_ turn: DeskForgeTurn, detail: DeskForgeDetail) -> some View {
        if turn.live?.running != true, let point = live.checkpoint(for: turn, in: sessionID), point.changed, !point.files.isEmpty {
            if point.undone {
                Label("Undone", systemImage: "arrow.uturn.backward").font(KFont.ui(13)).foregroundStyle(Palette.inkFaint)
            } else if !detail.ended {
                let undoing = live.isBusy("undo:" + point.id)
                let blocked = running || undoing || !point.canUndo
                VStack(alignment: .leading, spacing: 10) {
                    Text("This turn changed \(point.files.count) \(point.files.count == 1 ? "file" : "files")")
                        .font(KFont.ui(14.5, .medium)).foregroundStyle(Palette.ink)
                    HStack(spacing: 8) {
                        DeskPillButton(title: "Review", symbol: "eye") { go = .changes(sessionID) }
                        DeskPillButton(title: undoing ? "Undoing" : "Undo", symbol: "arrow.uturn.backward", tint: Palette.danger) {
                            sheet = .undo(point.id, point.files.count)
                        }
                        .disabled(blocked)
                        .opacity(blocked ? 0.4 : 1)
                    }
                    if point.overlap {
                        HintLine(text: "Other work ran in this folder at the same time, so this turn cannot be undone from here.")
                    } else if point.restored > 0 {
                        HintLine(text: "\(point.restored) of its changes were already put back, so the rest cannot be undone from here.")
                    }
                }
                .padding(14)
                .kCard(radius: 20)
            }
        }
    }

    private func undo(_ checkpoint: String) {
        Task {
            let outcome = await live.undo(sessionID, checkpoint: checkpoint)
            if let line = outcome.line {
                notice = line
            } else if outcome == .done {
                toast = "Turn undone. Files are back as they were."
            }
        }
    }

    // MARK: Composer

    private func composer(_ detail: DeskForgeDetail) -> some View {
        let stopping = live.transcript(sessionID).last?.live?.stopping == true || live.isBusy("stop:" + sessionID)
        return VStack(spacing: 8) {
            if let approval = live.approval(sessionID) {
                DeskForgeApprovalCard(sessionID: sessionID, approval: approval)
            }
            if let line = notice ?? live.note(sessionID) {
                DeskForgeLine(text: line, action: "OK") {
                    notice = nil
                    live.clearNote(sessionID)
                }
            }
            if detail.mode == .plan {
                NoteLine(text: "Plan mode: nothing changes until you switch to Build.", symbol: "list.bullet.clipboard")
                    .padding(.horizontal, 6)
            }
            GlassEffectContainer(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            modeSwitch(detail)
                            Button { sheet = .model } label: {
                                Chip(text: detail.modelOverride ?? live.modelName(detail.endpointID), symbol: "sparkle")
                            }
                            .buttonStyle(PressStyle())
                            .disabled(detail.ended)
                            .accessibilityLabel("Model, \(detail.modelOverride ?? live.modelName(detail.endpointID)). Change")
                            Button { sheet = .access } label: {
                                Chip(text: detail.fullAccess ? ForgeAccess.full.rawValue : ForgeAccess.supervised.rawValue,
                                     symbol: detail.fullAccess ? "bolt.shield.fill" : "checkmark.shield")
                                    .foregroundStyle(detail.fullAccess ? Palette.danger : Palette.ink)
                            }
                            .buttonStyle(PressStyle())
                            .disabled(detail.ended)
                            .accessibilityLabel("Permission mode, \(detail.fullAccess ? ForgeAccess.full.rawValue : ForgeAccess.supervised.rawValue)")
                        }
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.hidden)
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField(detail.ended ? "This session has ended" : (running ? "Wait for this turn to end" : "Ask, build, or describe a change"),
                                  text: $draft, axis: .vertical)
                            .font(KFont.ui(16.5))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1...5)
                            .focused($typing)
                            .disabled(detail.ended || sending)
                            .padding(.vertical, 11)
                        if running {
                            Button {
                                Haptics.thud()
                                Task {
                                    if let line = (await live.stop(sessionID)).line { notice = line }
                                }
                            } label: {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                    .frame(width: 36, height: 36)
                                    .background(Palette.ink.opacity(0.12), in: Circle())
                                    .frame(width: 44, height: 46)
                            }
                            .buttonStyle(PressStyle(scale: 0.88))
                            .disabled(stopping)
                            .opacity(stopping ? 0.45 : 1)
                            .accessibilityLabel(stopping ? "Stopping" : "Stop")
                        }
                        let canSend = hasText && !detail.ended && !running && !sending
                        Button(action: send) {
                            Image(systemName: sending ? "hourglass" : "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                                .foregroundStyle(canSend ? Palette.onGold : Palette.inkFaint)
                                .frame(width: 36, height: 36)
                                .background(canSend ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Palette.ink.opacity(0.08)), in: Circle())
                                .frame(width: 44, height: 46)
                        }
                        .buttonStyle(PressStyle(scale: 0.88))
                        .disabled(!canSend)
                        .accessibilityLabel(sending ? "Sending" : (running ? "Wait for this turn to end" : "Send"))
                    }
                    Text("\(detail.workspace) · \(detail.branch ?? "In place")")
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
        .animation(Motion.snappy, value: running)
    }

    /// Build or Plan. The other one is asked for with a confirm, and shows only once the desktop has switched.
    private func modeSwitch(_ detail: DeskForgeDetail) -> some View {
        let switching = live.isBusy("mode:" + sessionID)
        return HStack(spacing: 2) {
            ForEach(ForgeMode.allCases, id: \.self) { mode in
                let on = detail.mode == mode
                Button {
                    guard !on else { return }
                    Haptics.select()
                    sheet = .mode(mode)
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
        .disabled(running || detail.ended || switching)
        .opacity(running || switching ? 0.55 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
    }

    /// The words stay in the box until the desktop has taken them.
    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !running, !sending else { return }
        Haptics.tap()
        notice = nil
        Task {
            switch await live.send(text, to: sessionID) {
            case .done:
                if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
            case .busy:
                break
            case .refused(let line), .unconfirmed(let line):
                notice = line
            }
        }
    }

    private func setMode(_ mode: ForgeMode) {
        Task {
            if let line = (await live.setMode(sessionID, mode)).line { notice = line }
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetView(_ which: DeskForgeSessionSheet) -> some View {
        switch which {
        case .actions:
            actionsSheet
        case .model:
            DeskForgeModelSheet(current: detail?.endpointID, detail: modelDetail, changesSession: true) { picked in
                (await live.setModel(sessionID, endpointID: picked)).line
            }
        case .access:
            DeskForgeAccessSheet(sessionID: sessionID)
        case .end:
            DeskForgeEndSheet(sessionID: sessionID) { message, over in
                toast = message
                if over {
                    Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        dismiss()
                    }
                }
            }
        case .rename:
            DeskForgeRenameSheet(sessionID: sessionID, title: detail?.title ?? "")
        case .git:
            ForgeGitSheet(sessionID: sessionID) { path in open(.diff(session: sessionID, path: path)) }
        case .runApp:
            ConfirmSheet(title: "Start this app?",
                         detail: "Command: \(project?.appCommand ?? "")\nIt runs in this session's folder on your desktop. A command your desktop has not approved before is shown to you once more.",
                         confirm: "Start app", danger: false) {
                live.startApp(sessionID)
            }
        case .undo(let checkpoint, let files):
            ConfirmSheet(title: "Undo this turn?",
                         detail: "Puts back the \(files) \(files == 1 ? "file" : "files") this turn changed. Your desktop checks later edits first, and puts nothing back if one of them changed since.",
                         confirm: "Undo turn") {
                undo(checkpoint)
            }
        case .mode(let mode):
            ConfirmSheet(title: "Switch to \(mode.rawValue)?", detail: mode.explain, confirm: "Switch to \(mode.rawValue)", danger: false) {
                setMode(mode)
            }
        }
    }

    private var modelDetail: String? {
        guard let detail else { return nil }
        var parts = [live.modelName(detail.endpointID)]
        if let version = detail.modelOverride, !version.isEmpty { parts.append(version) }
        if let effort = detail.effort, !effort.isEmpty { parts.append("\(effort) effort") }
        return parts.joined(separator: " · ")
    }

    private func open(_ route: DesktopRoute) {
        sheet = nil
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            go = route
        }
    }

    private func then(_ next: DeskForgeSessionSheet) {
        sheet = nil
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            sheet = next
        }
    }

    private var actionsSheet: some View {
        let app = live.app(for: sessionID)
        let command = project?.appCommand ?? ""
        return FittedSheet(estimate: 680) {
            VStack(alignment: .leading, spacing: 14) {
                DeskSheetTitle(text: (detail?.title ?? "").isEmpty ? "Session" : (detail?.title ?? ""),
                               detail: "\(project?.name ?? "Forge") · \(live.modelName(detail?.endpointID))")
                HStack(spacing: 10) {
                    // One start at a time: not while an app runs, and not while a start waits on the desktop.
                    if app == nil && !command.isEmpty && live.approval(sessionID) == nil {
                        actionTile("play.fill", "Run app") { then(.runApp) }
                    }
                    actionTile("folder", "Explorer") { open(.explorer(sessionID)) }
                    actionTile("plusminus", "Changes") { open(.changes(sessionID)) }
                }
                .disabled(ended)
                .opacity(ended ? 0.45 : 1)
                if let app {
                    HintLine(text: "This session's app runs on port \(String(app.port)). Open it in Kairos on your desktop.", symbol: "play.circle")
                } else if command.isEmpty {
                    HintLine(text: "No app command is saved for this project. Set it in Kairos on your desktop.")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Saved app command")
                        Text(command)
                            .font(CodeFont.mono(12.5))
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HintLine(text: "Change it in Kairos on your desktop.")
                    }
                }
                VStack(spacing: 0) {
                    actionRow("arrow.triangle.branch", "Git", "Commit, push, pull and merge back") { then(.git) }
                    actionRow("pencil", "Rename") { then(.rename) }
                    actionRow("plus.bubble", "New session", "In \(project?.name ?? "this project")") {
                        live.composeProjectID = project?.id
                        ForgeStore.shared.composeRequested = true
                        open(.forgeHome)
                    }
                }
                .kCard(radius: 20)
                if let detail {
                    VStack(alignment: .leading, spacing: 6) {
                        NoteLine(text: detail.mode.explain, symbol: detail.mode == .build ? "hammer" : "list.bullet.clipboard")
                        NoteLine(text: detail.fullAccess ? "\(ForgeAccess.full.rawValue): \(ForgeAccess.full.explain)" : "\(ForgeAccess.supervised.rawValue): \(ForgeAccess.supervised.explain)",
                                 symbol: "checkmark.shield")
                        NoteLine(text: "The terminal and the app's page stay in Kairos on your desktop.", symbol: "desktopcomputer")
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
                .disabled(running || ended)
                .opacity(running || ended ? 0.45 : 1)
                if running {
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
