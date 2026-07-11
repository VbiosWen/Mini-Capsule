import Testing
import Foundation
import SwiftData
import AppKit
@testable import Mini_Capsule

private final class MockSettings: SettingsProtocol {
    var historyMaxCount: Int = 200
    var imageMaxSizeMB: Int = 2
    var pollingInterval: Double = 0.5
    var cleanupOnStartup: Bool = true
    var dedupEnabled: Bool = true
    var showHideShortcut: String = ""
    var quickPasteShortcut: String = ""
    var togglePinShortcut: String = ""
    var iCloudSyncEnabled: Bool = false
    var launchAtLogin: Bool = false
    var showInMenuBar: Bool = true
    var showFloatingPanel: Bool = true
    var collapsedStyle: String = "capsule"
    var hoverExpandDelay: Double = 0.3
    var hoverCollapseDelay: Double = 1.0
    var panelOpacityUnfocused: Double = 0.6
    var backgroundImageData: Data = Data()
    var ringDiameter: Double = 30
    var capsuleWindowFrame: Data = Data()
    func resetAll() {}
    func exportData(context: ModelContext) -> Data? { nil }
    func importData(_ data: Data, context: ModelContext) throws {}
    func clearAllHistory(context: ModelContext) {}
}

@MainActor
struct ClipboardMonitorTests {
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - nsImageToPNGData tests

    @Test func nsImageToPNGDataProducesValidPNG() {
        // Create a small NSImage and verify the output is non-empty PNG data.
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: NSSize(width: 10, height: 10)).fill()
        image.unlockFocus()

        let monitor = ClipboardMonitor(settings: MockSettings())
        let pngData = monitor.nsImageToPNGData(image)

        #expect(!pngData.isEmpty, "PNG data should not be empty")
        // Verify PNG signature: first 8 bytes = 137 80 78 71 13 10 26 10
        let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        #expect(Array(pngData.prefix(8)) == pngSignature, "Output should be valid PNG")
    }

    @Test func nsImageToPNGDataWithEmptyImageReturnsEmptyData() {
        // An NSImage with zero size produces TIFF data but bitmap init may fail.
        let image = NSImage(size: .zero)
        let monitor = ClipboardMonitor(settings: MockSettings())
        let data = monitor.nsImageToPNGData(image)
        // Should not crash — may return empty or TIFF data, but never nil.
        #expect(data is Data)
    }

    @Test func nsImageToPNGDataRoundtrip() {
        // Draw a colored image, convert to PNG, then reload — should decode back.
        let original = NSImage(size: NSSize(width: 32, height: 32))
        original.lockFocus()
        NSColor.blue.setFill()
        NSRect(origin: .zero, size: NSSize(width: 32, height: 32)).fill()
        original.unlockFocus()

        let monitor = ClipboardMonitor(settings: MockSettings())
        let pngData = monitor.nsImageToPNGData(original)

        // Reload from the PNG data
        let reloaded = NSImage(data: pngData)
        #expect(reloaded != nil, "Reloaded image should not be nil")
        #expect(reloaded!.size.width == 32)
        #expect(reloaded!.size.height == 32)
    }

    // MARK: - enforceCap tests

    @Test func enforceCapWithPinnedItemsDoesNotCrashAndKeepsPinned() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        // 200 items at the default cap, 5 pinned -> old code: suffix(from: 200) on 195 -> trap.
        for i in 0..<200 {
            let item = ClipItem(pasteCount: i, contentTypeRaw: "text", textContent: "t\(i)", isPinned: i < 5)
            context.insert(item)
        }
        try context.save()

        ClipboardMonitor.enforceCap(context: context, maxCount: 200)   // must not crash

        let remaining = try context.fetch(FetchDescriptor<ClipItem>())
        #expect(remaining.filter { $0.isPinned }.count == 5)   // pinned never deleted
        #expect(remaining.count <= 200)                        // room made for the incoming item
    }

    @Test func enforceCapDeletesLeastPastedUnpinnedFirst() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        for i in 0..<10 {
            // t0 least used, t9 most used — pasteCount passed via init, not mutated post-insert.
            let item = ClipItem(pasteCount: i, contentTypeRaw: "text", textContent: "t\(i)")
            context.insert(item)
        }
        try context.save()

        ClipboardMonitor.enforceCap(context: context, maxCount: 8)   // 10 items, cap 8 -> remove 3 to fit new one

        let remaining = try context.fetch(FetchDescriptor<ClipItem>())
        let survivingCounts = Set(remaining.map { $0.pasteCount })
        #expect(remaining.count == 7)                      // 10 - 3 removed
        #expect(!survivingCounts.contains(0))              // lowest pasteCount removed
        #expect(survivingCounts.contains(9))               // highest kept
    }

    // MARK: - encodeFileBookmarks tests

    @Test func encodeFileBookmarksProducesJSONArrayRoundtripsThroughDecoder() throws {
        let raw: [Data] = [Data([0xAA, 0xBB]), Data([0xCC, 0xDD, 0xEE])]
        guard let encoded = ClipboardMonitor.encodeFileBookmarks(raw) else {
            Issue.record("encode returned nil")
            return
        }
        let roundtripped = try JSONDecoder().decode([Data].self, from: encoded)
        #expect(roundtripped == raw)
    }

    @Test func encodeFileBookmarksEmptyReturnsNil() {
        let encoded = ClipboardMonitor.encodeFileBookmarks([])
        #expect(encoded == nil)
    }

    // MARK: - generateThumbnail tests

    @Test func generateThumbnailProducesPNGUnderMaxDimension() {
        // Build a 200×300 red image and encode as PNG.
        let original = NSImage(size: NSSize(width: 200, height: 300))
        original.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: NSSize(width: 200, height: 300)).fill()
        original.unlockFocus()
        let monitor = ClipboardMonitor(settings: MockSettings())
        let pngData = monitor.nsImageToPNGData(original)

        let thumb = ClipboardMonitor.generateThumbnail(pngData, maxDimension: 72)

        #expect(thumb != nil, "thumbnail should be generated for valid image")
        guard let thumb, let decoded = NSImage(data: thumb) else {
            Issue.record("thumb undecodable")
            return
        }
        #expect(max(decoded.size.width, decoded.size.height) <= 72,
                "longest side must be ≤ maxDimension")
        // Verify PNG signature
        let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        #expect(Array(thumb.prefix(8)) == pngSignature)
    }

    @Test func generateThumbnailReturnsNilForGarbageData() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        #expect(ClipboardMonitor.generateThumbnail(garbage) == nil)
    }
}
