import SwiftUI

/// The connection to the person's desktop: its state, the paired desktop, pair again, unpair this phone.
struct ConnectionScreen: View {
    var connection: Connection = .shared
    /// Debug pictures can show the list of paired phones without a desktop.
    var sampleDevices: [PhoneDeviceDTO] = []

    @Environment(\.dismiss) private var dismiss
    @State private var pairing = false
    @State private var confirmUnpair = false
    @State private var working = false
    @State private var devices: [PhoneDeviceDTO] = []
    @State private var devicesNote: String?
    @State private var removing: PhoneDeviceDTO?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero.arrives(0)
                if let desktop = connection.desktop, connection.state != .sample {
                    details(desktop).arrives(1)
                    if !shownDevices.isEmpty || devicesNote != nil { phones.arrives(2) }
                    actions.arrives(3)
                } else {
                    notPaired.arrives(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                GlassIconButton(symbol: "chevron.left", label: "Back") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background { HeaderFade() }
        }
        .kScreen(glowAt: UnitPoint(x: 0.5, y: -0.05))
        .sheet(isPresented: $pairing) {
            PairingForm(back: { pairing = false }, onPaired: { pairing = false }, connection: connection)
                .padding(.top, 18)
                .kSheet()
        }
        .confirmationDialog("Unpair this iPhone?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { unpair() }
            Button("Keep it paired", role: .cancel) {}
        } message: {
            Text("This iPhone will stop reaching your desktop and go back to sample data. You can pair it again with a new code.")
        }
        .confirmationDialog("Unpair that phone?", isPresented: removingShown, titleVisibility: .visible) {
            Button("Unpair \(removing?.name ?? "phone")", role: .destructive) { removeOther() }
            Button("Keep it", role: .cancel) { removing = nil }
        } message: {
            Text("It stops working at once. It can be paired again with a new code.")
        }
        .task(id: connection.state) { await loadDevices() }
        .animation(Motion.snappy, value: connection.state)
    }

    private var removingShown: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private var shownDevices: [PhoneDeviceDTO] { devices.isEmpty ? sampleDevices : devices }

    // MARK: Parts

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 88, height: 88)
                .kGlass(Circle())
            Text("Your desktop")
                .font(KFont.display(36))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 8) {
                stateDot
                Text(connection.statusLine)
                    .font(KFont.ui(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var stateDot: some View {
        switch connection.state {
        case .connected: Circle().fill(Palette.success).frame(width: 9, height: 9)
        case .connecting: PulsingDot(color: Palette.working, size: 8)
        case .offline: Circle().fill(Palette.gold).frame(width: 9, height: 9)
        case .signedOut: Circle().fill(Palette.danger).frame(width: 9, height: 9)
        case .sample: Circle().fill(Palette.inkFaint).frame(width: 9, height: 9)
        }
    }

    private func details(_ desktop: PairedDesktop) -> some View {
        VStack(spacing: 0) {
            infoRow("Address", desktop.host, symbol: "link")
            infoRow("Account", desktop.isAdmin ? "\(desktop.username) · admin" : desktop.username, symbol: "person.crop.circle")
            infoRow("Kairos", desktop.serverVersion.isEmpty ? desktop.serverName : "\(desktop.serverName) \(desktop.serverVersion)", symbol: "sparkle")
            infoRow("Last answer", lastAnswer, symbol: "clock", last: true)
        }
        .kCard(radius: 22)
    }

    private var lastAnswer: String {
        guard let date = connection.lastContact else { return connection.state == .connected ? "just now" : "not yet" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func infoRow(_ title: String, _ value: String, symbol: String, last: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.goldText)
                .frame(width: 26)
            Text(title).font(KFont.ui(16)).foregroundStyle(Palette.ink)
            Spacer(minLength: 12)
            Text(value)
                .font(KFont.ui(15))
                .foregroundStyle(Palette.inkDim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            if !last { Palette.line.frame(height: 1).padding(.leading, 54) }
        }
        .accessibilityElement(children: .combine)
    }

    private var phones: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Paired phones").padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(shownDevices.enumerated()), id: \.element.id) { index, device in
                    HStack(spacing: 12) {
                        Image(systemName: "iphone")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Palette.goldText)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name ?? "iPhone").font(KFont.ui(16)).foregroundStyle(Palette.ink)
                            Text(deviceLine(device))
                                .font(KFont.ui(13, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: 8)
                        if device.current == true {
                            Chip(text: "This iPhone")
                        } else {
                            Button { removing = device } label: {
                                Text("Unpair")
                                    .font(KFont.ui(14, .medium, relativeTo: .footnote))
                                    .foregroundStyle(Palette.danger)
                                    .frame(minWidth: 60, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("Unpair \(device.name ?? "phone")")
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 58)
                    .overlay(alignment: .bottom) {
                        if index < shownDevices.count - 1 { Palette.line.frame(height: 1).padding(.leading, 54) }
                    }
                }
                if let devicesNote {
                    Text(devicesNote)
                        .font(KFont.ui(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
            .kCard(radius: 22)
        }
    }

    private func deviceLine(_ device: PhoneDeviceDTO) -> String {
        var parts: [String] = []
        if let model = device.model, !model.isEmpty { parts.append(model) }
        if let seen = device.lastSeenAt?.date {
            parts.append("seen " + seen.formatted(date: .abbreviated, time: .shortened))
        } else if let made = device.createdAt?.date {
            parts.append("paired " + made.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.isEmpty ? "Paired" : parts.joined(separator: " · ")
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if case .offline = connection.state {
                actionRow("Try again now", symbol: "arrow.clockwise") {
                    Haptics.tap()
                    Task {
                        working = true
                        await connection.checkSession()
                        working = false
                    }
                }
            }
            actionRow(connection.state == .signedOut ? "Pair this iPhone again" : "Pair again with a new code", symbol: "qrcode") {
                pairing = true
            }
            if connection.state == .signedOut {
                actionRow("Go back to sample data", symbol: "sparkles") {
                    connection.forgetPairing()
                }
            } else {
                actionRow("Unpair this phone", symbol: "xmark.circle", danger: true) {
                    confirmUnpair = true
                }
            }
            if working { ProgressView().tint(Palette.gold).padding(.top, 4) }
        }
    }

    private func actionRow(_ title: String, symbol: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(danger ? Palette.danger : Palette.goldText)
                    .frame(width: 26)
                Text(title).font(KFont.ui(16, .medium)).foregroundStyle(danger ? Palette.danger : Palette.ink)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
            .kCard(radius: 20)
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .disabled(working)
    }

    private var notPaired: some View {
        VStack(spacing: 16) {
            Text("Pair this iPhone with your Kairos desktop to see your own chats and bots here. Until then the app shows sample data.")
                .font(KFont.ui(16))
                .foregroundStyle(Palette.inkDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 12)
            GoldButton(title: "Pair with your desktop") { pairing = true }
                .padding(.horizontal, 8)
            Text("On your desktop: Settings, Remote access, Pair the iPhone app.")
                .font(KFont.ui(13.5, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    // MARK: Work

    private func loadDevices() async {
        guard connection.state == .connected, sampleDevices.isEmpty else { return }
        do {
            devices = try await connection.devices()
            devicesNote = nil
        } catch {
            devicesNote = devices.isEmpty ? "The list of paired phones could not be read. " + APIError.plain(error) : nil
        }
    }

    private func unpair() {
        working = true
        Task {
            await connection.unpair()
            working = false
            Haptics.success()
        }
    }

    private func removeOther() {
        guard let device = removing else { return }
        removing = nil
        guard let client = connection.client else {
            devices.removeAll { $0.id == device.id }
            return
        }
        Task {
            do {
                try await client.phoneUnpair(deviceId: device.id)
                devices.removeAll { $0.id == device.id }
                Haptics.success()
            } catch {
                devicesNote = "That phone could not be unpaired. " + APIError.plain(error)
            }
        }
    }
}
