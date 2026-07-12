import Testing
import Foundation
import SwiftData
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.integration))
struct SettingsStoreDataTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test func exportThenImportRoundtripsText() throws {
        let ctx = try makeContext()
        ctx.insert(ClipItem(contentTypeRaw: "text", textContent: "alpha"))
        ctx.insert(ClipItem(contentTypeRaw: "text", textContent: "beta"))
        try ctx.save()
        let store = SettingsStore()

        let blob = try #require(store.exportData(context: ctx))
        let ctx2 = try makeContext()
        try store.importData(blob, context: ctx2)

        let texts = try ctx2.fetch(FetchDescriptor<ClipItem>()).compactMap { $0.textContent }
        #expect(Set(texts) == ["alpha", "beta"])
    }

    @Test func importSkipsDuplicateText() throws {
        let ctx = try makeContext()
        ctx.insert(ClipItem(contentTypeRaw: "text", textContent: "dup"))
        try ctx.save()
        let store = SettingsStore()
        let blob = try #require(store.exportData(context: ctx))   // contains "dup"

        try store.importData(blob, context: ctx)                  // import into same context
        let count = try ctx.fetch(FetchDescriptor<ClipItem>()).filter { $0.textContent == "dup" }.count
        #expect(count == 1)                                       // not duplicated
    }

    @Test func importImageRoundtripsViaBase64() throws {
        let ctx = try makeContext()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 7, 7, 7])
        ctx.insert(ClipItem(contentTypeRaw: "image", imageData: png,
                            imageMD5: ClipboardMonitor.md5Hash(png)))
        try ctx.save()
        let store = SettingsStore()
        let blob = try #require(store.exportData(context: ctx))
        let ctx2 = try makeContext()
        try store.importData(blob, context: ctx2)

        let img = try ctx2.fetch(FetchDescriptor<ClipItem>()).first { $0.contentTypeRaw == "image" }
        #expect(img?.imageData == png)
    }

    @Test func clearAllHistoryRemovesEverything() throws {
        let ctx = try makeContext()
        for i in 0..<5 { ctx.insert(ClipItem(contentTypeRaw: "text", textContent: "t\(i)")) }
        try ctx.save()
        SettingsStore().clearAllHistory(context: ctx)
        #expect(try ctx.fetch(FetchDescriptor<ClipItem>()).isEmpty)
    }
}
