import Foundation

/// The desktop's one live stream (`GET /api/chat/live/events`, server-sent events): every running turn of
/// the person's chats and bots. It reconnects by itself with a growing wait, and says when it is up or down.
final class LiveEventStream {
    /// One event's JSON, as it arrived.
    var onPacket: ((Data) -> Void)?
    /// true when the stream opens, false when it drops.
    var onState: ((Bool) -> Void)?
    /// The desktop refused the token.
    var onUnauthorized: (() -> Void)?

    private var task: Task<Void, Never>?
    private(set) var isOpen = false
    private(set) var lastPacketAt: Date?

    var isRunning: Bool { task != nil }

    func start(client: APIClient) {
        stop()
        task = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                do {
                    let bytes = try await client.openStream("/api/chat/live/events")
                    attempt = 0
                    self?.opened()
                    for try await line in bytes.lines {
                        if Task.isCancelled { return }
                        self?.received(line)
                    }
                } catch is CancellationError {
                    return
                } catch APIError.unauthorized {
                    self?.dropped()
                    self?.onUnauthorized?()
                    return
                } catch {
                    // Fall through to the wait below.
                }
                if Task.isCancelled { return }
                self?.dropped()
                attempt += 1
                let wait = LiveEventStream.backoff(attempt)
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if isOpen {
            isOpen = false
            onState?(false)
        }
    }

    /// 1, 2, 4, 8 ... up to 30 seconds, with a little spread so two phones do not knock together.
    static func backoff(_ attempt: Int) -> Double {
        let base = min(30.0, pow(2.0, Double(max(0, attempt - 1))))
        return base + Double.random(in: 0...0.6)
    }

    private func opened() {
        isOpen = true
        lastPacketAt = Date()
        onState?(true)
    }

    private func dropped() {
        guard isOpen else { return }
        isOpen = false
        onState?(false)
    }

    /// The desktop writes each event on one `data:` line and keepalives as comment lines.
    private func received(_ line: String) {
        lastPacketAt = Date()
        guard let payload = LiveEventStream.payload(of: line) else { return }
        onPacket?(Data(payload.utf8))
    }

    /// The JSON text of one stream line, or nil for a comment, a blank or another field.
    nonisolated static func payload(of line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let text = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}
