import Testing
import Foundation
@testable import Mini_Capsule

@Suite struct LogFacadeTests {
    @Test func facadeFansOutToAllSinks() {
        let a = InMemoryLogSink()
        let b = InMemoryLogSink()
        let log = Log(sinks: [a, b])
        log.log(.capture, .info, "poll", metadata: ["cc": "42"], correlationID: "x1")
        #expect(a.events.count == 1)
        #expect(b.events.count == 1)
        #expect(a.events.first?.message == "poll")
        #expect(a.events.first?.metadata["cc"] == "42")
        #expect(a.events.first?.correlationID == "x1")
    }

    @Test func ergonomicLogBuildsEventWithDefaults() {
        let sink = InMemoryLogSink()
        sink.log(.store, .error, "boom")
        let e = sink.events.first
        #expect(e?.category == .store)
        #expect(e?.level == .error)
        #expect(e?.metadata.isEmpty == true)
    }
}

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
