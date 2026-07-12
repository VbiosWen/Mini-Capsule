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
        let beforeCount = PasteService.beginSelfPaste()
        let item = ClipItem(contentTypeRaw: "text", textContent: "self-paste-\(UUID())")
        // Simulate write pattern: clearContents + setString
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.textContent ?? "", forType: .string)
        PasteService.endSelfPaste(begin: beforeCount)

        let endCount = NSPasteboard.general.changeCount
        // All changeCounts from begin through end should be suppressed.
        for cc in beforeCount...endCount {
            #expect(PasteService.shouldSuppress(changeCount: cc) == true,
                    "changeCount \(cc) should be suppressed (range \(beforeCount)...\(endCount))")
        }
        // The next changeCount after the range should NOT be suppressed.
        #expect(PasteService.shouldSuppress(changeCount: endCount + 1) == false)
    }

    @Test func rangeBasedSuppressionDoesNotSuppressOutsideRange() {
        let before = PasteService.beginSelfPaste()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("test", forType: .string)
        PasteService.endSelfPaste(begin: before)
        let after = NSPasteboard.general.changeCount

        // A changeCount far outside the range should not be suppressed.
        #expect(PasteService.shouldSuppress(changeCount: after + 100) == false)
    }

    @Test func suppressedSetCleanedUpOnLargeSize() {
        // Manually insert 250 values into the suppressed set.
        let before = PasteService.beginSelfPaste()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("cleanup-test", forType: .string)
        PasteService.endSelfPaste(begin: before)

        // Add many more values — the set should be bounded.
        for _ in 0..<250 {
            let b = PasteService.beginSelfPaste()
            pb.clearContents()
            pb.setString("bulk", forType: .string)
            PasteService.endSelfPaste(begin: b)
        }
        // Should not crash and should still be functional.
        let b2 = PasteService.beginSelfPaste()
        pb.clearContents()
        pb.setString("after-cleanup", forType: .string)
        PasteService.endSelfPaste(begin: b2)
        let end2 = NSPasteboard.general.changeCount
        #expect(PasteService.shouldSuppress(changeCount: end2) == true)
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
