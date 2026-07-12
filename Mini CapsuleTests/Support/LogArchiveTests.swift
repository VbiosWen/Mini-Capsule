import Testing
import Foundation
@testable import Mini_Capsule

@Suite struct LogArchiveTests {
    @Test func writesChainToConfiguredDir() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-\(UUID().uuidString)", isDirectory: true)
        setenv("MC_TEST_LOG_DIR", dir.path, 1)
        defer { unsetenv("MC_TEST_LOG_DIR") }

        let events = [
            LogEvent(category: .capture, level: .info, message: "poll", correlationID: "c1"),
            LogEvent(category: .store, level: .info, message: "insert", correlationID: "c1"),
        ]
        LogArchive.write(events, testID: "Suite/case name!")

        let file = dir.appendingPathComponent("logs/Suite_case_name_.jsonl")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 2)
    }

    @Test func noopWhenEnvUnset() {
        unsetenv("MC_TEST_LOG_DIR")
        // Must not crash and must not create anything.
        LogArchive.write([LogEvent(category: .app, level: .info, message: "x")], testID: "t")
    }
}
