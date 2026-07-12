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

@Suite(.tags(.integration))
struct SystemSeamTests {
    @Test func fakeWorkspaceReturnsStubbedIdentity() {
        let ws = FakeWorkspace(bundleID: "com.apple.Safari", appName: "Safari")
        #expect(ws.bundleID == "com.apple.Safari")
        #expect(ws.appName == "Safari")
    }

    @Test func fakeAccessibilityHonorsTrustFlag() {
        #expect(FakeAccessibility(isTrusted: true).isTrusted)
        #expect(!FakeAccessibility(isTrusted: false).isTrusted)
    }

    @Test func fakeKeyInjectorRecordsCalls() {
        let k = FakeKeyInjector()
        k.pasteViaCommandV()
        k.pasteViaCommandV()
        #expect(k.pasteCallCount == 2)
    }
}
