import Foundation
@testable import Mini_Capsule

/// Always-capture archival: writes a test's full log chain to
/// `$MC_TEST_LOG_DIR/logs/<testID>.jsonl`. The runner promotes failing tests'
/// files into `failures/`. No-op when the env var is unset (e.g. Xcode runs).
enum LogArchive {
    static func write(_ events: [LogEvent], testID: String) {
        guard let root = ProcessInfo.processInfo.environment["MC_TEST_LOG_DIR"], !root.isEmpty else { return }
        let logsDir = URL(fileURLWithPath: root).appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let safe = testID.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let file = logsDir.appendingPathComponent("\(String(safe)).jsonl")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var blob = Data()
        for e in events {
            guard let d = try? encoder.encode(e) else { continue }
            blob.append(d); blob.append(0x0A)
        }
        try? blob.write(to: file)
    }
}
