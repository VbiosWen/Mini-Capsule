import Testing
import Foundation
import AppKit
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.unit))
struct ImageHelpersTests {
    private func monitor() -> ClipboardMonitor {
        ClipboardMonitor(settings: MockSettingsForSeams(), pasteboard: FakePasteboard())
    }
    private func t(_ raw: String) -> NSPasteboard.PasteboardType { .init(raw) }

    private func realPNG(_ side: CGFloat) -> Data {
        let img = NSImage(size: NSSize(width: side, height: side))
        img.lockFocus(); NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: side, height: side).fill(); img.unlockFocus()
        return monitor().nsImageToPNGData(img)
    }

    @Test func capImageSizeReturnsUnchangedWhenUnderLimit() {
        let png = realPNG(8)
        let out = monitor().capImageSize(png, maxBytes: 5_000_000)
        #expect(out == png)                                  // untouched
    }

    @Test func capImageSizeRecompressesWhenOverLimit() {
        let png = realPNG(128)                               // hundreds of bytes+
        let out = monitor().capImageSize(png, maxBytes: 100) // force recompress
        #expect(out != png)                                  // changed
        #expect(NSImage(data: out) != nil)                   // still a valid image
    }

    @Test func capImageSizeLeavesGarbageUntouched() {
        let junk = Data([0, 1, 2, 3, 4, 5])
        #expect(monitor().capImageSize(junk, maxBytes: 1) == junk)  // NSImage(data:) fails → unchanged
    }

    @Test func md5HashIsDeterministicAndDiffersByContent() {
        let a = Data("hello".utf8), b = Data("world".utf8)
        #expect(ClipboardMonitor.md5Hash(a) == ClipboardMonitor.md5Hash(a))
        #expect(ClipboardMonitor.md5Hash(a) != ClipboardMonitor.md5Hash(b))
        #expect(ClipboardMonitor.md5Hash(a).count == 32)     // 16 bytes hex
    }

    @Test func extractFileNameReadsFromFileURL() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pic.png")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let pb = FakePasteboard()
        pb.stubbedReadObjects = [url]
        #expect(monitor().extractFileName(from: pb, types: [.fileURL]) == "pic.png")
    }

    @Test func extractFileNameReturnsNilWithoutFileURL() {
        let pb = FakePasteboard()
        #expect(monitor().extractFileName(from: pb, types: [.string]) == nil)
    }
}
