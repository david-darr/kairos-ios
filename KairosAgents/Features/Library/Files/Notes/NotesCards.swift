import SwiftUI

// The pieces of the Notes section: the capture card, the stat tiles and one note card.

/// "Capture a thought...", an optional due time, and "Add note".
struct NotesCaptureCard: View {
    @Binding var draft: String
    @Binding var hasDue: Bool
    @Binding var due: Date
    var focused: FocusState<Bool>.Binding
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.goldText)
                    .accessibilityHidden(true)
                TextField("Capture a thought...", text: $draft)
                    .font(KFont.ui(16.5))
                    .foregroundStyle(Palette.ink)
                    .focused(focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .accessibilityLabel("New note")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))

            Toggle(isOn: $hasDue.animation(Motion.snappy)) {
                Text("Add a due time")
                    .font(KFont.ui(15.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
            }
            .tint(Palette.gold)
            .frame(minHeight: 44)

            if hasDue {
                DatePicker(selection: $due, displayedComponents: [.date, .hourAndMinute]) {
                    Text("Due time")
                        .font(KFont.ui(15.5, relativeTo: .subheadline))
                        .foregroundStyle(Palette.inkDim)
                }
                .tint(Palette.gold)
                .frame(minHeight: 44)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            GoldButton(title: "Add note", action: add)
        }
        .padding(16)
        .kCard(radius: 24, raised: true)
    }
}

/// A small tile with a big number: "Finished", "Due this week".
struct NotesStatTile: View {
    let symbol: String
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.goldText)
                .frame(width: 36, height: 36)
                .background(Palette.gold.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(KFont.ui(22, .semibold, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                Text(label)
                    .font(KFont.ui(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .kCard(radius: 20)
        .accessibilityElement(children: .combine)
    }
}

/// What a long press on a note can ask for.
enum NotesCardAction {
    case edit, pin, due, details, delete
}

/// One note: a check circle, the text (clamped to three lines), its due label and a pin.
struct NotesCard: View {
    let note: KNote
    /// Done as drawn: flips the moment it is tapped, before the note moves groups.
    let showsDone: Bool
    let toggle: () -> Void
    let act: (NotesCardAction) -> Void

    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    private var canExpand: Bool { expanded || fullHeight > shownHeight + 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button(action: toggle) {
                CheckCircle(on: showsDone)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.88))
            .accessibilityLabel(showsDone ? "Reopen: \(note.text)" : "Complete: \(note.text)")
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Button { act(.details) } label: { noteText }
                    .buttonStyle(PressStyle(scale: 0.99))
                    .accessibilityLabel("Note details: \(note.text)")
                metaRow
            }
            .padding(.vertical, 12)
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 20, raised: note.pinned && !note.done)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu { menu }
    }

    private var noteText: some View {
        Text(note.text)
            .font(KFont.ui(16.5))
            .foregroundStyle(showsDone ? Palette.inkFaint : Palette.ink)
            .strikethrough(showsDone, color: Palette.inkFaint)
            .lineLimit(expanded ? nil : 3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { value in
                shownHeight = value
            }
            .background(alignment: .topLeading) {
                Text(note.text)
                    .font(KFont.ui(16.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { value in
                        fullHeight = value
                    }
            }
            .animation(Motion.gentle, value: showsDone)
            .contentShape(Rectangle())
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if note.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.goldText)
                    .accessibilityLabel("Pinned")
            }
            dueLabel
            Spacer(minLength: 4)
            if canExpand {
                Button(expanded ? "Show less" : "Show more") {
                    Haptics.tap()
                    withAnimation(Motion.snappy) { expanded.toggle() }
                }
                .font(KFont.ui(14, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.goldText)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
                .buttonStyle(PressStyle())
            }
        }
    }

    @ViewBuilder
    private var dueLabel: some View {
        if let due = note.due {
            let overdue = NotesDue.isOverdue(note)
            HStack(spacing: 4) {
                Image(systemName: overdue ? "exclamationmark.circle" : "clock")
                    .font(.system(size: 11, weight: .semibold))
                Text(FilesDates.short(due))
                    .font(KFont.ui(13, overdue ? .medium : .regular, relativeTo: .footnote))
            }
            .foregroundStyle(overdue ? Palette.danger : Palette.inkFaint)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(overdue ? "Overdue, \(FilesDates.full(due))" : "Due \(FilesDates.full(due))")
        } else {
            Text("No date")
                .font(KFont.ui(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Edit", systemImage: "pencil") { act(.edit) }
        Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") { act(.pin) }
        Button(note.due == nil ? "Add due time" : "Change due time", systemImage: "clock") { act(.due) }
        Button("Details", systemImage: "info.circle") { act(.details) }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { act(.delete) }
    }
}
