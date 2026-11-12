import SwiftUI
import UIKit

// Account, Accounts on this device, and the add-account sign-in (with password reset).
// Everything runs on YouStore's sample accounts until the desktop connection fills it in.

// MARK: - Small shared pieces

nonisolated enum AccountSheetKind: String, Identifiable, Hashable, Sendable {
    case pin, password
    var id: String { rawValue }
}

nonisolated enum AccountSignInStep: Hashable, Sendable {
    case signIn, forgot, code
}

nonisolated private enum AccountUnlockMode: Hashable, Sendable {
    case pin, password
}

nonisolated private struct AccountUnlock: Identifiable, Hashable, Sendable {
    let account: DeviceAccount
    var mode: AccountUnlockMode
    var id: String { account.id }
}

/// The title block at the top of an account sheet.
private struct AccountSheetTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(KFont.ui(20, .semibold, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// An inline error under a form.
private struct AccountErrorLine: View {
    let text: String?

    var body: some View {
        if let text {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(KFont.ui(14.5, relativeTo: .subheadline))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Palette.danger)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityElement(children: .combine)
        }
    }
}

/// A hidden number field for PINs, in the same card look as the form rows.
private struct AccountPinField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(KFont.ui(13, .medium, relativeTo: .footnote))
                .foregroundStyle(Palette.inkFaint)
            SecureField("4 to 8 digits", text: $text)
                .keyboardType(.numberPad)
                .font(KFont.ui(18, .medium))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .kCard(radius: 22)
    }
}

// MARK: - Account

/// The signed-in account: who you are, its colour, the switching PIN, the password and two-step sign-in.
struct AccountScreen: View {
    private let store = YouStore.shared
    @State private var sheet: AccountSheetKind? = nil
    @State private var enrolling = false
    @State private var code = ""
    @State private var codeError: String? = nil
    @State private var confirmRemovePin = false
    @State private var confirmTurnOff = false
    @State private var passwordNote: String? = nil
    @State private var copied = false

    /// A made-up setup key in the usual authenticator format.
    private let setupKey = "JBSW Y3DP EHPK 3PXP"

    init(startSheet: AccountSheetKind? = nil, startEnrolling: Bool = false) {
        _sheet = State(initialValue: startSheet)
        _enrolling = State(initialValue: startEnrolling)
    }

    var body: some View {
        let account = store.current
        SettingsPage("Account", subtitle: "Who you are on this Kairos, and how you sign in.") {
            SettingsGroup {
                identityRow(account)
                StatusRow(
                    title: "This computer",
                    detail: account.isAdmin
                        ? "Admins can always run commands and open files on the desktop."
                        : "Your chats and bots can't run commands or open files on the desktop. Ask an admin if you need that.",
                    symbol: "desktopcomputer",
                    status: account.isAdmin ? "Allowed" : "Not allowed",
                    tone: account.isAdmin ? .ok : .muted
                )
            }
            .arrives(0)

            SettingsGroup("Switching accounts") {
                colourRow(account)
                pinRow(account)
            }
            .arrives(1)

            SettingsGroup("Password", footer: passwordNote) {
                ActionRow(title: "Change password", detail: "Your current password, then a new one.", symbol: "key") {
                    sheet = .password
                }
            }
            .arrives(2)

            SettingsGroup("Two-step sign-in") {
                StatusRow(
                    title: "Authenticator app",
                    detail: "A code from your authenticator app on every sign-in.",
                    symbol: "checkmark.shield",
                    status: account.twoStep ? "On" : "Off",
                    tone: account.twoStep ? .ok : .muted
                )
                if account.twoStep {
                    ActionRow(title: "Turn off two-step sign-in", tone: .danger) { confirmTurnOff = true }
                } else if enrolling {
                    enrolment
                } else {
                    ActionRow(title: "Turn on two-step sign-in", symbol: "plus", tone: .gold) {
                        withAnimation(Motion.snappy) { enrolling = true }
                    }
                }
            }
            .arrives(3)

            SettingsGroup {
                YouNavRow(
                    title: "Accounts on this device",
                    detail: store.accounts.count == 1 ? "1 signed in on this phone" : "\(store.accounts.count) signed in on this phone",
                    symbol: "person.2",
                    to: .accounts
                )
            }
            .arrives(4)
        }
        .sheet(item: $sheet) { kind in
            switch kind {
            case .pin: AccountPinSetSheet()
            case .password: AccountPasswordSheet { passwordNote = "Password changed." }
            }
        }
        .confirmationDialog("Remove the switching PIN?", isPresented: $confirmRemovePin, titleVisibility: .visible) {
            Button("Remove PIN", role: .destructive) {
                withAnimation(Motion.snappy) { store.update { $0.pin = nil } }
                store.say("The PIN is removed.")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone holding a device where this account is signed in can then switch into it with one tap.")
        }
        .alert("Turn off two-step sign-in?", isPresented: $confirmTurnOff) {
            Button("Turn off", role: .destructive) {
                withAnimation(Motion.snappy) { store.update { $0.twoStep = false } }
                store.say("Two-step sign-in is off")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signing in will need only your password.")
        }
    }

    // MARK: Rows

    private func identityRow(_ account: DeviceAccount) -> some View {
        HStack(spacing: 14) {
            AccountAvatar(account: account, size: 58)
                .animation(Motion.bouncy, value: account.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(KFont.display(28))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(account.isAdmin ? "Admin on this Kairos" : "Member on this Kairos")
                    .font(KFont.ui(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 8)
            StatusPill(text: account.role, tone: account.isAdmin ? .warn : .muted)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private func colourRow(_ account: DeviceAccount) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RowLabel(
                title: "Account colour",
                detail: "On your avatar and the account switcher, so it is always clear whose account is open.",
                symbol: "paintpalette"
            )
            HStack(spacing: 0) {
                ForEach(YouStore.accountColors.indices, id: \.self) { index in
                    let colour = YouStore.accountColors[index]
                    swatch(name: colour.name, hex: colour.hex, on: account.colorHex == colour.hex)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func swatch(name: String, hex: UInt32, on: Bool) -> some View {
        Button {
            Haptics.select()
            withAnimation(Motion.bouncy) { store.update { $0.colorHex = hex } }
            store.say("Colour changed to \(name)")
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 32, height: 32)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.onGold)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Palette.ink.opacity(on ? 0.85 : 0), lineWidth: 2)
                    .padding(-5)
            )
            .scaleEffect(on ? 1.06 : 1)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func pinRow(_ account: DeviceAccount) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RowLabel(
                    title: "Switching PIN",
                    detail: "Asked when someone switches into this account on a device where it is signed in. Wrong tries make them wait.",
                    symbol: "lock"
                )
                StatusPill(text: account.pin == nil ? "Off" : "On", tone: account.pin == nil ? .muted : .ok)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            RowButtons {
                YouPillButton(title: account.pin == nil ? "Set a PIN" : "Change PIN", symbol: "lock", prominent: account.pin == nil) {
                    sheet = .pin
                }
                if account.pin != nil {
                    YouPillButton(title: "Remove PIN", danger: true) { confirmRemovePin = true }
                }
            }
        }
    }

    private var enrolment: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add this key to your authenticator app, then enter the 6-digit code it shows.")
                .font(KFont.ui(14.5, relativeTo: .subheadline))
                .foregroundStyle(Palette.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup key")
                        .font(KFont.ui(12.5, .medium, relativeTo: .caption))
                        .foregroundStyle(Palette.inkFaint)
                    Text(setupKey)
                        .font(KFont.ui(17, .medium))
                        .tracking(1.5)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 4)
                YouPillButton(title: copied ? "Copied" : "Copy", symbol: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = setupKey.replacingOccurrences(of: " ", with: "")
                    withAnimation(Motion.snappy) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(Motion.snappy) { copied = false }
                    }
                }
            }
            .padding(12)
            .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(spacing: 8) {
                TextField("6-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .font(KFont.ui(17, .medium))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .kCard(radius: 16, raised: true)
                YouPillButton(title: "Confirm", prominent: true) { confirmCode() }
            }
            AccountErrorLine(text: codeError)
            YouPillButton(title: "Cancel") {
                withAnimation(Motion.snappy) {
                    enrolling = false
                    code = ""
                    codeError = nil
                }
            }
        }
        .padding(16)
        .transition(.opacity)
    }

    private func confirmCode() {
        let digits = code.filter(\.isNumber)
        guard digits.count == 6, digits.count == code.count else {
            withAnimation(Motion.snappy) { codeError = "Enter the 6-digit code from your authenticator app." }
            Haptics.thud()
            return
        }
        if digits == "000000" {
            withAnimation(Motion.snappy) { codeError = "That code did not match. Check the time on your phone and try again." }
            Haptics.thud()
            return
        }
        withAnimation(Motion.snappy) {
            store.update { $0.twoStep = true }
            enrolling = false
            code = ""
            codeError = nil
        }
        Haptics.success()
        store.say("Two-step sign-in is on")
    }
}

/// Set or change the switching PIN. The password is asked first.
private struct AccountPinSetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var pin = ""
    @State private var error: String? = nil
    private let store = YouStore.shared

    var body: some View {
        FittedSheet(estimate: 480) {
            VStack(alignment: .leading, spacing: 16) {
                AccountSheetTitle(
                    title: store.current.pin == nil ? "Set a switching PIN" : "Change the switching PIN",
                    detail: "Asked when someone switches into \(store.current.name) on a device where it is signed in."
                )
                SettingsGroup {
                    FieldRow(title: "Your password", text: $password, prompt: "Password", secure: true)
                }
                AccountPinField(title: "PIN", text: $pin)
                AccountErrorLine(text: error)
                GoldButton(title: "Save PIN") { save() }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.top, 30)
            .padding(.bottom, 20)
            .animation(Motion.snappy, value: error)
        }
    }

    private func save() {
        guard !password.isEmpty else { error = "Enter your password."; Haptics.thud(); return }
        let digits = pin.filter(\.isNumber)
        guard digits.count == pin.count, (4...8).contains(pin.count) else {
            error = "The PIN is 4 to 8 digits."
            Haptics.thud()
            return
        }
        let chosen = pin
        withAnimation(Motion.snappy) { store.update { $0.pin = chosen } }
        Haptics.success()
        store.say("Switching into this account now asks the PIN.")
        dismiss()
    }
}

/// Change the password: the current one, then a new one.
private struct AccountPasswordSheet: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var error: String? = nil
    @State private var busy = false
    private let store = YouStore.shared

    var body: some View {
        FittedSheet(estimate: 480) {
            VStack(alignment: .leading, spacing: 16) {
                AccountSheetTitle(title: "Change password", detail: "The new password works on every device at once.")
                SettingsGroup {
                    FieldRow(title: "Current password", text: $current, prompt: "Current password", secure: true)
                    FieldRow(title: "New password", text: $new, prompt: "8 or more characters", secure: true)
                }
                AccountErrorLine(text: error)
                GoldButton(title: busy ? "Changing..." : "Change password") { change() }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.top, 30)
            .padding(.bottom, 20)
            .animation(Motion.snappy, value: error)
        }
    }

    private func change() {
        guard !busy else { return }
        error = nil
        guard !current.isEmpty else { error = "Enter your current password."; Haptics.thud(); return }
        guard new.count >= 8 else { error = "The new password needs 8 or more characters."; Haptics.thud(); return }
        guard new != current else { error = "Pick a new password, not the current one."; Haptics.thud(); return }
        busy = true
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            busy = false
            Haptics.success()
            onDone()
            store.say("Password changed.")
            dismiss()
        }
    }
}

// MARK: - Accounts on this device

/// Every account signed in on this phone: switch, sign out of one, add one, sign out of all.
struct DeviceAccountsScreen: View {
    private let store = YouStore.shared
    @State private var unlocking: AccountUnlock? = nil
    @State private var signingOut: DeviceAccount? = nil
    @State private var confirmAll = false
    @State private var started = false
    private let startFull: Bool

    init(startSwitchID: String? = nil, startFull: Bool = false) {
        self.startFull = startFull
        if let id = startSwitchID, let account = YouStore.shared.accounts.first(where: { $0.id == id }) {
            _unlocking = State(initialValue: AccountUnlock(account: account, mode: account.expired ? .password : .pin))
        }
    }

    var body: some View {
        SettingsPage("Accounts on this device", subtitle: "Every account signed in on this phone. Switch between them with one tap.") {
            SettingsGroup("Signed in", footer: "An account with a PIN asks it before it opens. A sign-in that ran out asks for the password again.") {
                ForEach(store.accounts) { account in
                    accountRow(account)
                }
            }
            .arrives(0)

            SettingsGroup {
                if store.accounts.count < 9 {
                    YouNavRow(title: "Add another account", detail: "It joins the accounts on this phone.", symbol: "plus", to: .signIn)
                } else {
                    ActionRow(
                        title: "Add another account",
                        detail: "This phone already has 9 accounts signed in. Sign out of one first.",
                        symbol: "plus"
                    ) {
                        store.say("Sign out of one account first")
                    }
                }
                ActionRow(title: "Sign out of all accounts", symbol: "power", tone: .danger) { confirmAll = true }
            }
            .arrives(1)
        }
        .animation(Motion.snappy, value: store.accounts)
        .sheet(item: $unlocking) { unlock in
            AccountUnlockSheet(unlock: unlock)
        }
        .confirmationDialog(
            "Sign out of \(signingOut?.name ?? "this account")?",
            isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }),
            titleVisibility: .visible,
            presenting: signingOut
        ) { account in
            Button("Sign out", role: .destructive) {
                withAnimation(Motion.snappy) { store.signOut(account.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It leaves this phone. Its chats and bots stay on the desktop.")
        }
        .alert("Sign out of all accounts?", isPresented: $confirmAll) {
            Button("Sign out of all", role: .destructive) { signOutAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every account leaves this phone. Signing in again needs the password.")
        }
        .onAppear {
            guard !started else { return }
            started = true
            if startFull { fillToLimit() }
        }
    }

    private func mark(_ account: DeviceAccount) -> (text: String, tone: StatusPill.Tone) {
        if account.expired { return ("Sign in again", .warn) }
        if account.id == store.currentID { return ("Open now", .ok) }
        if account.pin != nil { return ("PIN on this phone", .muted) }
        return ("One tap", .muted)
    }

    private func accountRow(_ account: DeviceAccount) -> some View {
        let isOpen = account.id == store.currentID
        let canSwitch = !isOpen || account.expired
        let canSignOut = store.accounts.count > 1
        let state = mark(account)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                AccountAvatar(account: account, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(KFont.ui(16.5, .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(account.role)
                        .font(KFont.ui(13.5, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: 8)
                StatusPill(text: state.text, tone: state.tone)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, canSwitch || canSignOut ? 0 : 12)
            .accessibilityElement(children: .combine)
            if canSwitch || canSignOut {
                RowButtons {
                    if canSwitch {
                        YouPillButton(
                            title: account.expired ? (isOpen ? "Sign in again" : "Sign in") : "Switch",
                            symbol: account.pin != nil && !account.expired ? "lock" : nil,
                            prominent: true
                        ) {
                            begin(account)
                        }
                    }
                    if canSignOut {
                        YouPillButton(title: "Sign out", danger: true) { signingOut = account }
                    }
                }
            }
        }
    }

    private func begin(_ account: DeviceAccount) {
        if account.expired {
            unlocking = AccountUnlock(account: account, mode: .password)
        } else if account.pin != nil {
            unlocking = AccountUnlock(account: account, mode: .pin)
        } else {
            Haptics.success()
            withAnimation(Motion.snappy) { store.switchTo(account.id) }
        }
    }

    private func signOutAll() {
        let keep = store.currentID
        withAnimation(Motion.snappy) {
            store.accounts.removeAll { $0.id != keep }
            store.update { $0.expired = true }
        }
        store.say("Signed out of all accounts")
    }

    private func fillToLimit() {
        let names = ["Studio", "Garden", "Club", "Market", "Office", "Lab", "Workshop", "Choir"]
        var index = 0
        while store.accounts.count < 9 && index < names.count {
            let colour = YouStore.accountColors[index % YouStore.accountColors.count].hex
            store.accounts.append(DeviceAccount(id: "a-fill-\(index)", name: names[index], colorHex: colour, isAdmin: false))
            index += 1
        }
    }
}

/// Switching into an account that asks its PIN, or signing in again with the password.
private struct AccountUnlockSheet: View {
    let unlock: AccountUnlock
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var triesLeft = 5
    @State private var error: String? = nil
    @State private var usePassword = false
    private let store = YouStore.shared

    var body: some View {
        let byPassword = usePassword || unlock.mode == .password
        let name = unlock.account.name
        FittedSheet(estimate: 460) {
            VStack(alignment: .leading, spacing: 16) {
                AccountAvatar(account: unlock.account, size: 56)
                    .frame(maxWidth: .infinity)
                AccountSheetTitle(
                    title: unlock.account.expired ? "Sign in to \(name)" : "Switch to \(name)",
                    detail: unlock.account.expired
                        ? "That sign-in has expired. Enter the password."
                        : (byPassword ? "Enter the password for \(name)." : "This account asks its PIN on this phone.")
                )
                if byPassword {
                    SettingsGroup {
                        FieldRow(title: "Password", text: $entry, prompt: "Password", secure: true)
                    }
                } else {
                    AccountPinField(title: "PIN", text: $entry)
                }
                AccountErrorLine(text: error)
                GoldButton(title: byPassword ? "Sign in" : "Switch") { submit(byPassword: byPassword) }
                QuietButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, 18)
            .padding(.top, 30)
            .padding(.bottom, 20)
            .animation(Motion.snappy, value: error)
            .animation(Motion.snappy, value: usePassword)
        }
    }

    private func submit(byPassword: Bool) {
        if byPassword {
            guard !entry.isEmpty else { error = "Enter the password."; Haptics.thud(); return }
            guard entry.count >= 4 else { error = "That password is not right. Try again."; Haptics.thud(); return }
            if let index = store.accounts.firstIndex(where: { $0.id == unlock.account.id }) {
                store.accounts[index].expired = false
            }
            finish()
            return
        }
        let digits = entry.filter(\.isNumber)
        guard digits.count == entry.count, (4...8).contains(entry.count) else {
            error = "The PIN is 4 to 8 digits."
            Haptics.thud()
            return
        }
        if entry == unlock.account.pin {
            finish()
            return
        }
        triesLeft -= 1
        entry = ""
        Haptics.thud()
        if triesLeft > 0 {
            error = "Wrong PIN. \(triesLeft) \(triesLeft == 1 ? "try" : "tries") left."
        } else {
            usePassword = true
            error = "Too many wrong tries. Enter the password instead."
        }
    }

    private func finish() {
        Haptics.success()
        withAnimation(Motion.snappy) { store.switchTo(unlock.account.id) }
        dismiss()
    }
}

// MARK: - Sign in to another account

/// Add another account on this phone, with the 2FA step and the password reset inside the same screen.
/// On sample data the username "two" asks for a 2FA code.
struct SignInScreen: View {
    @Environment(\.dismiss) private var dismiss
    private let store = YouStore.shared
    @State private var step: AccountSignInStep = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var twoCode = ""
    @State private var needsCode = false
    @State private var email = ""
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var error: String? = nil
    @State private var info: String? = nil
    @State private var busy = false

    init(startStep: AccountSignInStep = .signIn, startUsername: String = "", startNeedsCode: Bool = false, startError: String? = nil) {
        _step = State(initialValue: startStep)
        _username = State(initialValue: startUsername)
        _needsCode = State(initialValue: startNeedsCode)
        _error = State(initialValue: startError)
    }

    private var title: String {
        switch step {
        case .signIn: "Add another account"
        case .forgot: "Reset password"
        case .code: "Enter your code"
        }
    }

    private var subtitle: String {
        switch step {
        case .signIn: "It joins the accounts on this phone. Switch between them with one tap."
        case .forgot: "Enter your username and the email address connected in Mail. If they match, a code goes out to that address."
        case .code: "Check the inbox for the email you entered. The code expires in 15 minutes."
        }
    }

    var body: some View {
        SettingsPage(title, subtitle: subtitle) {
            switch step {
            case .signIn: signInForm
            case .forgot: forgotForm
            case .code: codeForm
            }
        }
        .animation(Motion.snappy, value: step)
        .animation(Motion.snappy, value: error)
        .animation(Motion.snappy, value: needsCode)
    }

    // MARK: Forms

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let info {
                NoteText(text: info, symbol: "checkmark")
            }
            SettingsGroup {
                FieldRow(title: "Username", text: $username, prompt: "Username")
                FieldRow(title: "Password", text: $password, prompt: "Password", secure: true)
                if needsCode {
                    FieldRow(title: "2FA code", text: $twoCode, prompt: "6-digit code", keyboard: .numberPad)
                }
            }
            AccountErrorLine(text: error)
            GoldButton(title: busy ? "Logging in..." : "Log in") { logIn() }
            QuietButton(title: "Forgot password?") { go(.forgot) }
        }
    }

    private var forgotForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup {
                FieldRow(title: "Username", text: $username, prompt: "Username")
                FieldRow(title: "Connected email address", text: $email, prompt: "name@example.com", keyboard: .emailAddress)
            }
            AccountErrorLine(text: error)
            GoldButton(title: busy ? "Sending..." : "Send code") { sendCode() }
            QuietButton(title: "Back to sign in") { go(.signIn) }
        }
    }

    private var codeForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup {
                FieldRow(title: "6-digit code", text: $resetCode, prompt: "123456", keyboard: .numberPad)
                FieldRow(title: "New password (8+ characters)", text: $newPassword, prompt: "New password", secure: true)
            }
            AccountErrorLine(text: error)
            GoldButton(title: busy ? "Resetting..." : "Reset password") { reset() }
            QuietButton(title: "Start over") { go(.forgot) }
        }
    }

    // MARK: Actions

    private func go(_ next: AccountSignInStep) {
        withAnimation(Motion.snappy) {
            step = next
            error = nil
            if next != .signIn { info = nil }
        }
    }

    private func fail(_ text: String) {
        withAnimation(Motion.snappy) { error = text }
        Haptics.thud()
    }

    private func logIn() {
        guard !busy else { return }
        error = nil
        info = nil
        let typed = username.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty, !password.isEmpty else { fail("Enter your username and password."); return }
        guard store.accounts.count < 9 else { fail("This phone already has 9 accounts signed in. Sign out of one first."); return }
        let name: String = String(typed.prefix(1)).uppercased() + String(typed.dropFirst())
        if store.accounts.contains(where: { $0.name.lowercased() == typed.lowercased() }) {
            fail("\(name) is already signed in on this phone. Switch to it from Accounts on this device.")
            return
        }
        guard password.count >= 4 else { fail("That username and password do not match."); return }
        if typed.lowercased() == "two" {
            if !needsCode {
                withAnimation(Motion.snappy) { needsCode = true }
                fail("Enter the 2FA code from your authenticator app.")
                return
            }
            let digits = twoCode.filter(\.isNumber)
            guard digits.count == 6, digits.count == twoCode.count else { fail("The 2FA code is 6 digits."); return }
        }
        busy = true
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            busy = false
            Haptics.success()
            store.addAccount(name: name)
            dismiss()
        }
    }

    private func sendCode() {
        guard !busy else { return }
        let user = username.trimmingCharacters(in: .whitespaces)
        let address = email.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !address.isEmpty else { fail("Enter both your username and the connected email."); return }
        guard address.contains("@") else { fail("That email address is missing an @."); return }
        busy = true
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            busy = false
            go(.code)
            store.say("If they match, a code is on its way")
        }
    }

    private func reset() {
        guard !busy else { return }
        let digits = resetCode.filter(\.isNumber)
        guard digits.count == 6, digits.count == resetCode.count else { fail("Enter the 6-digit code from the email."); return }
        guard newPassword.count >= 8 else { fail("The new password needs 8 or more characters."); return }
        if digits == "000000" { fail("That code is wrong or has expired. Start over to get a new one."); return }
        busy = true
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            busy = false
            Haptics.success()
            password = ""
            resetCode = ""
            newPassword = ""
            withAnimation(Motion.snappy) {
                step = .signIn
                error = nil
                info = "Password reset. Log in with the new one."
            }
        }
    }
}

// MARK: - Debug pictures

enum AccountDebug {
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "account": return AnyView(AccountScreen())
        case "account-pin": return AnyView(AccountScreen(startSheet: .pin))
        case "account-password": return AnyView(AccountScreen(startSheet: .password))
        case "account-twostep": return AnyView(AccountScreen(startEnrolling: true))
        case "account-devices": return AnyView(DeviceAccountsScreen())
        case "account-devices-pin": return AnyView(DeviceAccountsScreen(startSwitchID: "a-shop"))
        case "account-devices-expired": return AnyView(DeviceAccountsScreen(startSwitchID: "a-home"))
        case "account-devices-full": return AnyView(DeviceAccountsScreen(startFull: true))
        case "account-signin": return AnyView(SignInScreen())
        case "account-signin-2fa": return AnyView(SignInScreen(startUsername: "two", startNeedsCode: true, startError: "Enter the 2FA code from your authenticator app."))
        case "account-forgot": return AnyView(SignInScreen(startStep: .forgot))
        case "account-reset-code": return AnyView(SignInScreen(startStep: .code, startUsername: "sam"))
        default: return nil
        }
    }
}
