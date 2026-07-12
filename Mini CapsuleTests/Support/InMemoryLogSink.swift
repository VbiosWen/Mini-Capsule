import Foundation
@testable import Mini_Capsule

/// Test sink that records events in order. Thread-safe.
final class InMemoryLogSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [LogEvent] = []

    var events: [LogEvent] { lock.withLock { _events } }
    func write(_ event: LogEvent) { lock.withLock { _events.append(event) } }
    func events(in category: LogCategory) -> [LogEvent] { events.filter { $0.category == category } }
    func messages() -> [String] { events.map(\.message) }
    func reset() { lock.withLock { _events.removeAll() } }
}
