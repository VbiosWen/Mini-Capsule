import Testing
import Foundation
import SwiftData
@testable import Mini_Capsule

@MainActor
struct ClipboardMonitorTests {
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

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
}
