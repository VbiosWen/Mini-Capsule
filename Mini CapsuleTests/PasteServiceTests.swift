// Mini CapsuleTests/PasteServiceTests.swift
import Testing
import AppKit
@testable import Mini_Capsule

@MainActor
struct PasteServiceTests {

    @Test func keyCodeForVReturnsNonZero() async throws {
        let keyCode = PasteService.keyCodeForV()
        // Should return a valid key code (>0) or the fallback 0x09
        #expect(keyCode != 0)
    }

    @MainActor
    @Test func copyToClipboardArmsSuppressionForItsOwnChange() {
        let item = ClipItem(contentTypeRaw: "text", textContent: "self-paste-\(UUID())")
        PasteService.copyToClipboard(item)
        let count = NSPasteboard.general.changeCount
        // The change we just made is suppressed exactly once, then released.
        #expect(PasteService.shouldSuppress(changeCount: count) == true)
        #expect(PasteService.shouldSuppress(changeCount: count) == false)
    }
}
