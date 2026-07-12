import Testing
import Foundation
@testable import Mini_Capsule

@Suite struct FileSinkTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filesink-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func writesOneJSONLinePerEvent() throws {
        let dir = tempDir()
        let sink = FileSink(directory: dir, fileName: "t.jsonl")
        sink.write(LogEvent(category: .capture, level: .info, message: "a"))
        sink.write(LogEvent(category: .store, level: .error, message: "b"))

        let text = try String(contentsOf: sink.fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let first = try decoder.decode(LogEvent.self, from: Data(lines[0].utf8))
        #expect(first.message == "a")
    }

    @Test func rotatesWhenOverMaxBytes() throws {
        let dir = tempDir()
        let sink = FileSink(directory: dir, fileName: "t.jsonl", maxBytes: 200)
        for i in 0..<50 { sink.write(LogEvent(category: .app, level: .info, message: "line-\(i)")) }
        let rotated = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("t-") && $0.hasSuffix(".jsonl") }
        #expect(!rotated.isEmpty, "expected at least one rotated file")
    }
}
