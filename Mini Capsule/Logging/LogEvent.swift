import Foundation

/// One log subsystem. One os.Logger category maps to each case.
enum LogCategory: String, Codable, Sendable, CaseIterable {
    case capture, dedup, store, paste, hotkey, settings, window, menubar, cleanup, ui, app
}

enum LogLevel: Int, Codable, Sendable, Comparable {
    case debug, info, notice, warning, error, fault
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A single structured log record. `metadata` holds counts/types/ids ONLY —
/// never clipboard content. `correlationID` threads one capture/paste chain.
struct LogEvent: Codable, Sendable, Equatable {
    let timestamp: Date
    let category: LogCategory
    let level: LogLevel
    let message: String
    let metadata: [String: String]
    let correlationID: String?

    init(category: LogCategory,
         level: LogLevel,
         message: String,
         metadata: [String: String] = [:],
         correlationID: String? = nil,
         timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.message = message
        self.metadata = metadata
        self.correlationID = correlationID
    }
}
