import Testing
import Foundation
@testable import Mini_Capsule

@Suite(.tags(.unit))
struct ModelInitTests {
    @Test func clipItemDefaultsAreSane() {
        let before = Date()
        let item = ClipItem(contentTypeRaw: "text")
        #expect(item.contentTypeRaw == "text")
        #expect(item.pasteCount == 0)
        #expect(item.isPinned == false)
        #expect(item.textContent == nil)
        #expect(item.imageData == nil)
        #expect(item.sortOrder == nil)
        #expect(item.lastPastedAt == nil)
        #expect(item.timestamp >= before)                 // defaults to ~now
        #expect(item.sourceAppBundleID == nil)
    }

    @Test func clipItemPreservesProvidedValues() {
        let ts = Date(timeIntervalSince1970: 1000)
        let item = ClipItem(timestamp: ts, pasteCount: 7, contentTypeRaw: "image",
                            imageData: Data([1, 2]), imageFileName: "a.png",
                            imageMD5: "abc", isPinned: true, sortOrder: 3,
                            sourceAppBundleID: "com.test")
        #expect(item.timestamp == ts)
        #expect(item.pasteCount == 7)
        #expect(item.imageFileName == "a.png")
        #expect(item.imageMD5 == "abc")
        #expect(item.isPinned)
        #expect(item.sortOrder == 3)
        #expect(item.sourceAppBundleID == "com.test")
    }

    @Test func clipItemIDsAreUnique() {
        #expect(ClipItem(contentTypeRaw: "text").id != ClipItem(contentTypeRaw: "text").id)
    }

    @Test func legacyItemStoresTimestamp() {
        let ts = Date(timeIntervalSince1970: 500)
        #expect(Item(timestamp: ts).timestamp == ts)
    }
}
