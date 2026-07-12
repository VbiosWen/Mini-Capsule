import Testing
import Foundation
@testable import Mini_Capsule

@Suite struct OSLogSinkTests {
    @Test func formatLineIncludesCorrelationMessageAndSortedMetadata() {
        let e = LogEvent(category: .capture, level: .info, message: "readPasteboard",
                         metadata: ["type": "image", "bytes": "48213"], correlationID: "a1b2")
        let line = OSLogSink.formatLine(e)
        #expect(line == "[a1b2] readPasteboard bytes=48213 type=image")
    }

    @Test func formatLineWithoutCorrelationOmitsBracket() {
        let e = LogEvent(category: .app, level: .notice, message: "launch")
        #expect(OSLogSink.formatLine(e) == "launch")
    }

    @Test func writeDoesNotCrash() {
        // Smoke test: os.Logger output isn't assertable here; just ensure no trap.
        OSLogSink().write(LogEvent(category: .app, level: .debug, message: "x"))
    }
}
