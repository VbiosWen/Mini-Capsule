import Testing
import Foundation
@testable import Mini_Capsule

@Suite struct LogEventTests {
    @Test func eventDefaultsAreEmpty() {
        let e = LogEvent(category: .capture, level: .info, message: "hi")
        #expect(e.metadata.isEmpty)
        #expect(e.correlationID == nil)
        #expect(e.category == .capture)
        #expect(e.level == .info)
        #expect(e.message == "hi")
    }

    @Test func levelIsComparable() {
        #expect(LogLevel.debug < LogLevel.error)
        #expect(LogLevel.fault > LogLevel.warning)
    }

    @Test func eventRoundTripsThroughCodable() throws {
        let e = LogEvent(category: .store, level: .error, message: "save failed",
                         metadata: ["id": "E7", "count": "3"], correlationID: "a1b2")
        let data = try JSONEncoder().encode(e)
        let decoded = try JSONDecoder().decode(LogEvent.self, from: data)
        #expect(decoded == e)
    }
}
