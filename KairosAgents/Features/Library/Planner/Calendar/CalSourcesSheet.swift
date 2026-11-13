import SwiftUI

// MARK: - Your calendars

/// Which calendars show, the Google account, the period buttons and the way into the Archive.
struct CalSourcesSheet: View {
    @Bindable var store: CalStore
    let onArchive: () -> Void
    let onOpenGoogle: () -> Void

    @State private var notice: String?

    var body: some View {
        FittedSheet(estimate: 760) {
            VStack(alignment: .leading, spacing: 18) {
                PlannerSheetTitle(title: "Your calendars", subtitle: store.periodLabel)

                HStack(spacing: 10) {
                    PlannerPill(title: "Previous period", symbol: "chevron.left", style: .quiet, expand: true) {
                        withAnimation(Motion.snappy) { store.shift(-1) }
                    }
                    PlannerPill(title: "Next period", symbol: "chevron.right", style: .quiet, expand: true) {
                        withAnimation(Motion.snappy) { store.shift(1) }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "On your computer")
                    VStack(spacing: 0) {
                        sourceRow("Kairos", detail: "Events made in Kairos", color: Palette.gold, source: .kairos)
                        sourceRow("Notes with due times", detail: "From Notes", color: Color(hex: CalSampleProvider.notesHex), source: .notes)
                        sourceRow("Workspace deadlines", detail: "From your tabs, like CRM", color: Color(hex: CalSampleProvider.tabHex), source: .tab, last: true)
                    }
                    .kCard(radius: 20)
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Google")
                    if store.googleConnected {
                        googleCard
                    } else if !store.isSample, let note = store.liveGoogleNote {
                        CalLiveLine(text: note)
                    } else {
                        disconnected
                    }
                }

                VStack(spacing: 0) {
                    Button(action: onArchive) {
                        GroupRow(title: "Archive", symbol: "archivebox", value: "\(store.archived.count)", last: true)
                    }
                    .buttonStyle(PressStyle(scale: 0.99))
                    .accessibilityHint("Checked-off events and notes")
                }
                .kCard(radius: 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .plannerNotice($notice)
    }

    private func sourceRow(_ title: String, detail: String, color: Color, source: CalSourceKind, last: Bool = false) -> some View {
        swatchToggle(title, detail: detail, color: color, last: last, isOn: Binding(
            get: { !store.hiddenSources.contains(source) },
            set: { _ in store.toggleSource(source) }
        ))
    }

    private func swatchToggle(_ title: String, detail: String?, color: Color, last: Bool, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: Binding(get: { isOn.wrappedValue }, set: { value in
            Haptics.select()
            withAnimation(Motion.snappy) { isOn.wrappedValue = value }
        })) {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 12, height: 12).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
                    if let detail {
                        Text(detail).font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                }
            }
        }
        .tint(Palette.gold)
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 54) }
        }
    }

    private var googleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("G")
                    .font(KFont.ui(18, .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.accountEmail).font(KFont.ui(16, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    HStack(spacing: 6) {
                        Circle().fill(Palette.success).frame(width: 7, height: 7)
                        Text("Connected").font(KFont.ui(13, relativeTo: .footnote)).foregroundStyle(Palette.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }

            ForEach(Array(store.calendars.enumerated()), id: \.element.id) { index, calendar in
                swatchToggle(calendar.name, detail: calendar.writable ? nil : "Read-only", color: Color(hex: calendar.colorHex),
                             last: index == store.calendars.count - 1,
                             isOn: Binding(get: { calendar.visible }, set: { value in
                                 if store.isSample {
                                     store.setVisible(calendar.id, value)
                                 } else {
                                     store.setVisibleLive(calendar.id, value) { notice = $0 }
                                 }
                             }))
            }

            Text("New events go to \(store.calendar(store.defaultCalendarID)?.name ?? "Kairos") · Google by default.")
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.ink.opacity(0.04))

            HStack(spacing: 10) {
                PlannerPill(title: "Manage connection", style: .quiet, expand: true, action: onOpenGoogle)
                PlannerPill(title: "Connect another", symbol: "plus", style: .outline, expand: true) {
                    notice = "Add calendar accounts on the computer running Kairos."
                }
            }
            .padding(12)
        }
        .kCard(radius: 20)
    }

    private var disconnected: some View {
        PlannerEmpty(title: "Connect your calendar", hint: "Connect Google in Library to see your calendars here.",
                     pose: .idle, actionTitle: "Open Google connection", action: onOpenGoogle)
    }
}

// MARK: - Archive

/// Checked-off events and notes, newest first, each with Reopen.
struct CalArchiveSheet: View {
    @Bindable var store: CalStore
    @State private var notice: String?

    var body: some View {
        FittedSheet(estimate: 520) {
            VStack(alignment: .leading, spacing: 16) {
                PlannerSheetTitle(title: "Archive")
                Text("Checked-off events and notes. Reopen to bring one back to the active calendar.")
                    .font(KFont.ui(15))
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)

                if store.archived.isEmpty {
                    PlannerEmpty(title: "Nothing archived yet.", hint: "When you check off an event or a note, it lands here.")
                        .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(store.archived.enumerated()), id: \.element.id) { index, event in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Palette.success)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(KFont.ui(16, .medium))
                                        .foregroundStyle(Palette.ink)
                                        .strikethrough(true, color: Palette.inkFaint)
                                        .lineLimit(1)
                                    Text("\(event.source == .notes ? "Note" : "Event") · \(CalDates.dayTitle(event.start))")
                                        .font(KFont.ui(13.5, relativeTo: .footnote))
                                        .foregroundStyle(Palette.inkFaint)
                                }
                                Spacer(minLength: 6)
                                PlannerPill(title: "Reopen", style: .quiet) {
                                    if store.isSample {
                                        withAnimation(Motion.snappy) { store.reopen(event.id) }
                                        notice = "Back on your calendar"
                                    } else {
                                        Task { notice = await store.reopenLive(event) ?? "Back on your calendar" }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                if index < store.archived.count - 1 { Palette.line.frame(height: 1).padding(.leading, 48) }
                            }
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .kCard(radius: 20)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .plannerNotice($notice)
        .task { await store.loadArchiveLive() }
    }
}
