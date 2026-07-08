import Testing
import Foundation
import SwiftData
@testable import Mini_Capsule

@MainActor
struct FrequencyCleanupServiceTests {
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func keepCountFollowsHistoryMaxCountNotHardcoded50() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let settings = SettingsStore()
        settings.historyMaxCount = 120                      // > 50 on purpose
        for i in 0..<200 {
            let item = ClipItem(contentTypeRaw: "text", textContent: "t\(i)")
            item.pasteCount = i
            context.insert(item)
        }
        try context.save()

        FrequencyCleanupService.performCleanup(context: context, keepCount: nil, settings: settings)

        let remaining = try context.fetch(FetchDescriptor<ClipItem>())
        #expect(remaining.count == 120)                    // not 50
        settings.resetAll()
    }

    @Test func pinnedItemsAreExemptFromCleanup() throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        let settings = SettingsStore()
        settings.historyMaxCount = 5
        for i in 0..<20 {
            let item = ClipItem(contentTypeRaw: "text", textContent: "t\(i)", isPinned: i < 8)
            item.pasteCount = i
            context.insert(item)
        }
        try context.save()

        FrequencyCleanupService.performCleanup(context: context, keepCount: nil, settings: settings)

        let remaining = try context.fetch(FetchDescriptor<ClipItem>())
        #expect(remaining.filter { $0.isPinned }.count == 8)   // all pins survive even beyond keep
        settings.resetAll()
    }
}
