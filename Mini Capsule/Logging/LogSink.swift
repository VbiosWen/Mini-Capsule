import Foundation

/// A destination for log events. Implementations must be thread-safe.
protocol LogSink: Sendable {
    func write(_ event: LogEvent)
}

extension LogSink {
    /// Ergonomic entry point: build a `LogEvent` and write it.
    func log(_ category: LogCategory,
             _ level: LogLevel,
             _ message: String,
             metadata: [String: String] = [:],
             correlationID: String? = nil) {
        write(LogEvent(category: category, level: level, message: message,
                       metadata: metadata, correlationID: correlationID))
    }
}

/// Fan-out facade. Production wires an OSLogSink + FileSink; tests inject an
/// InMemoryLogSink. Services depend on `LogSink` (default `Log.shared`).
final class Log: LogSink, @unchecked Sendable {
    static let shared = Log(sinks: [OSLogSink(), FileSink()])
    private let sinks: [LogSink]
    init(sinks: [LogSink]) { self.sinks = sinks }
    func write(_ event: LogEvent) {
        for sink in sinks { sink.write(event) }
    }
}
