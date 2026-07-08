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

    @Test func decodeFileBookmarksReturnsArrayForJSONEncodedBlob() throws {
        let bookmarks: [Data] = [Data([0x01, 0x02]), Data([0x03, 0x04, 0x05])]
        let encoded = try JSONEncoder().encode(bookmarks)
        let decoded = PasteService.decodeFileBookmarks(encoded)
        #expect(decoded.count == 2)
        #expect(decoded[0] == Data([0x01, 0x02]))
        #expect(decoded[1] == Data([0x03, 0x04, 0x05]))
    }

    @Test func decodeFileBookmarksLegacyBlobReturnsSingleElement() {
        // Legacy: raw bookmark Data written by old versions (not JSON).
        let legacy = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let decoded = PasteService.decodeFileBookmarks(legacy)
        #expect(decoded == [legacy])
    }

    @Test func decodeFileBookmarksEmptyJSONArrayFallsBackToLegacy() throws {
        // JSON `[]` is decodable but semantically empty — the safest read is
        // to treat the blob as legacy so we never silently drop content.
        let encoded = try JSONEncoder().encode([Data]())
        let decoded = PasteService.decodeFileBookmarks(encoded)
        #expect(decoded == [encoded])
    }
}
