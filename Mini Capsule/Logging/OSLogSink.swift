import Foundation
import os

/// Routes events to Apple's unified logging. Each LogCategory becomes an
/// os.Logger category under one subsystem, visible in Console.app / `log stream`.
struct OSLogSink: LogSink {
    static let subsystem = "com.minicapsule.app"

    /// Pure formatter (unit-testable). Metadata is rendered as sorted `k=v` pairs
    /// so output is deterministic. Content never reaches here by construction.
    static func formatLine(_ event: LogEvent) -> String {
        let meta = event.metadata
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        let cid = event.correlationID.map { "[\($0)] " } ?? ""
        let base = "\(cid)\(event.message)"
        return meta.isEmpty ? base : "\(base) \(meta)"
    }

    func write(_ event: LogEvent) {
        let logger = Logger(subsystem: Self.subsystem, category: event.category.rawValue)
        let line = Self.formatLine(event)
        // `.private` is a second guard; by policy `line` already excludes content.
        switch event.level {
        case .debug:   logger.debug("\(line, privacy: .private)")
        case .info:    logger.info("\(line, privacy: .private)")
        case .notice:  logger.notice("\(line, privacy: .private)")
        case .warning: logger.warning("\(line, privacy: .private)")
        case .error:   logger.error("\(line, privacy: .private)")
        case .fault:   logger.fault("\(line, privacy: .private)")
        }
    }
}
