import SwiftUI

nonisolated enum ComputerControl: Hashable, Sendable { case kairos, you, closed }

nonisolated enum PointerMode: String, CaseIterable, Hashable, Sendable {
    case click = "Click", scroll = "Scroll", move = "Move view"
}

nonisolated enum ComputerShot: String, CaseIterable, Hashable, Sendable {
    case before = "Before", after = "After", click = "Click"
}

nonisolated struct ComputerStepInfo: Identifiable, Sendable {
    let id = UUID()
    var action: String
    var result: String
    var failed = false
    /// Where the click landed, in the 1280 by 800 screen, when the step was a click.
    var point: CGPoint? = nil
    /// Why no picture was kept, when none was.
    var missing: String? = nil
    var typed: String = ""
}

nonisolated struct ComputerRun: Identifiable, Sendable {
    let id: String
    var when: String
    var steps: [ComputerStepInfo]
}

nonisolated struct ComputerRipple: Identifiable, Sendable {
    let id = UUID()
    var point: CGPoint
}

/// What the Computer screen reads and changes.
protocol ComputerProviding: AnyObject {
    var control: ComputerControl { get }
    var lastAction: String { get }
    var runs: [ComputerRun] { get }
}

@Observable
final class ComputerStore: ComputerProviding {
    var control: ComputerControl = .kairos
    var lastAction = "Last action 9:41: typed the order note"
    var typed = "Order 1042: two blue bells, one bike lock."
    var scroll: CGFloat = 0
    var recording = false
    var recordedSteps = 0
    var modifiers: Set<String> = []
    var runs: [ComputerRun] = ComputerSample.runs

    var hasControl: Bool { control == .you }

    func takeOver() {
        control = .you
        lastAction = "You have control. Kairos is waiting."
        Haptics.thud()
    }

    func handBack() {
        if recording { recording = false }
        control = .kairos
        modifiers = []
        lastAction = "Kairos has control again."
        Haptics.tap()
    }

    func stop() {
        recording = false
        control = .closed
        modifiers = []
        lastAction = "Computer closed. The last picture is kept."
        Haptics.thud()
    }

    func reconnect() {
        control = .kairos
        lastAction = "Watching your desktop again."
    }

    func click(at point: CGPoint) {
        let x = Int(point.x.rounded())
        let y = Int(point.y.rounded())
        let combo = modifierPrefix()
        lastAction = "\(combo)Click at \(x), \(y)"
        modifiers = []
        note()
    }

    func drag(from: CGPoint, to: CGPoint) {
        lastAction = "Drag from \(Int(from.x)), \(Int(from.y)) to \(Int(to.x)), \(Int(to.y))"
        note()
    }

    func scrollBy(_ amount: CGFloat) {
        scroll = min(max(0, scroll + amount), 260)
        lastAction = amount > 0 ? "Scroll down" : "Scroll up"
        note()
    }

    func type(_ text: String) {
        typed += text
        lastAction = "Typed \"\(text.count > 18 ? String(text.prefix(18)) + "..." : text)\""
        note()
    }

    func key(_ name: String) {
        if ["Ctrl", "Alt", "Win"].contains(name) {
            if modifiers.contains(name) { modifiers.remove(name) } else { modifiers.insert(name) }
            Haptics.select()
            return
        }
        let full = modifierPrefix() + name
        switch full {
        case "Backspace":
            if !typed.isEmpty { typed.removeLast() }
        case "Enter":
            typed += "\n"
        case "Ctrl+V":
            typed += " Pick up Friday."
        default:
            break
        }
        lastAction = "Pressed \(full)"
        modifiers = []
        Haptics.tap()
        note()
    }

    func toggleRecording() -> Bool {
        recording.toggle()
        if recording {
            recordedSteps = 0
            lastAction = "Recording your steps"
            return false
        }
        lastAction = "Recording stopped"
        return true
    }

    private func modifierPrefix() -> String {
        ["Ctrl", "Alt", "Win"].filter { modifiers.contains($0) }.map { $0 + "+" }.joined()
    }

    private func note() {
        if recording { recordedSteps += 1 }
    }
}

nonisolated enum ComputerSample {
    static let runs: [ComputerRun] = [
        ComputerRun(id: "r-1", when: "Today 9:38", steps: [
            ComputerStepInfo(action: "open the Notepad window", result: "Notepad is in front"),
            ComputerStepInfo(action: "click (412, 268) 'New note'", result: "A blank note opened", point: CGPoint(x: 412, y: 268)),
            ComputerStepInfo(action: "type 'Order 1042: two blue bells, one bike lock.'", result: "Typed 43 characters", typed: "Order 1042: two blue bells, one bike lock."),
            ComputerStepInfo(action: "click (980, 140) 'Save'", result: "The save window did not open", failed: true, point: CGPoint(x: 980, y: 140), typed: "Order 1042: two blue bells, one bike lock."),
            ComputerStepInfo(action: "type into the password field", result: "Done", missing: "This step's screenshot was not kept: private field", typed: "Order 1042: two blue bells, one bike lock."),
        ]),
        ComputerRun(id: "r-2", when: "Yesterday 16:05", steps: [
            ComputerStepInfo(action: "open the shop page", result: "The page loaded"),
            ComputerStepInfo(action: "scroll down 3", result: "Done"),
            ComputerStepInfo(action: "click (640, 520) 'Add to cart'", result: "The cart shows 1 item", point: CGPoint(x: 640, y: 520)),
        ]),
    ]
}
