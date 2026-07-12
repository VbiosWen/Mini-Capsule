import Testing
import Foundation
import AppKit
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.unit))
struct ReadPasteboardImageTests {
    private func monitor() -> ClipboardMonitor {
        ClipboardMonitor(settings: MockSettingsForSeams(), pasteboard: FakePasteboard())
    }
    private func t(_ raw: String) -> NSPasteboard.PasteboardType { .init(raw) }

    /// A small real PNG so capImageSize (under the 2 MB default) returns it unchanged.
    private func smallPNG() -> Data {
        let img = NSImage(size: NSSize(width: 4, height: 4))
        img.lockFocus(); NSColor.green.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); img.unlockFocus()
        return ClipboardMonitor(settings: MockSettingsForSeams()).nsImageToPNGData(img)
    }

    @Test func eachKnownImageUTIReturnsImagePreservingData() {
        let utis: [NSPasteboard.PasteboardType] = [
            .png, .tiff, t("public.jpeg"), t("com.compuserve.gif"),
            t("public.heic"), t("public.heif"), t("com.microsoft.bmp"),
        ]
        let raw = smallPNG()
        for uti in utis {
            let pb = FakePasteboard()
            pb.stubbedData[uti] = raw
            let result = monitor().readPasteboard(pb, types: [uti])
            #expect(result?.type == "image", "UTI \(uti.rawValue) should yield image")
            #expect(result?.image == raw, "UTI \(uti.rawValue) should preserve raw bytes")
        }
    }

    @Test func nsImageFallbackConvertsToImage() {
        let pb = FakePasteboard()
        let img = NSImage(size: NSSize(width: 6, height: 6))
        img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 6, height: 6).fill(); img.unlockFocus()
        pb.stubbedReadObjects = [img]                          // read objects returns an NSImage
        let result = monitor().readPasteboard(pb, types: [t("com.weird.custom")])   // not a known image UTI
        #expect(result?.type == "image")
        #expect((result?.image?.count ?? 0) > 0)
        #expect(NSImage(data: result!.image!) != nil)          // decodable PNG
    }

    @Test func pdfIsCapturedAsImage() {
        let pb = FakePasteboard()
        let pdf = Data([0x25, 0x50, 0x44, 0x46, 1, 2, 3])       // "%PDF" + bytes
        pb.stubbedData[.pdf] = pdf
        let result = monitor().readPasteboard(pb, types: [.pdf])
        #expect(result?.type == "image")
        #expect(result?.image == pdf)
        #expect(result?.fileName?.hasSuffix(".pdf") == true)
    }
}
