import Testing
import Foundation
import AppKit
@testable import Mini_Capsule

@Suite(.tags(.integration))
struct PasteboardSeamTests {
    @Test func nsPasteboardConformsToReadingAndWriting() {
        let pb: PasteboardReading & PasteboardWriting = NSPasteboard.withUniqueName()
        pb.clearContents()
        _ = pb.setString("hi", forType: .string)
        #expect(pb.string(forType: .string) == "hi")
        #expect(pb.changeCount >= 1)
    }

    @Test func fakePasteboardRecordsWritesAndServesReads() {
        let fake = FakePasteboard()
        fake.stubbedTypes = [.string]
        fake.stubbedStrings[.string] = "hello"
        #expect(fake.string(forType: .string) == "hello")
        #expect(fake.types == [.string])
        _ = fake.setData(Data([1, 2, 3]), forType: .png)
        #expect(fake.writtenData[.png] == Data([1, 2, 3]))
        #expect(fake.clearCount == 1)
    }
}
