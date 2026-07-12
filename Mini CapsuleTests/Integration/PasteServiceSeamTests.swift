import Testing
import Foundation
import SwiftData
import AppKit
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.integration))
struct PasteServiceSeamTests {
    private static func makeContext() throws -> ModelContext {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test func copyWritesTextAndMarksSuppression() {
        let pb = FakePasteboard()
        let tracker = SelfPasteTracker()
        let log = InMemoryLogSink()
        let item = ClipItem(contentTypeRaw: "text", textContent: "hello world")

        PasteService.copyToClipboard(item, pasteboard: pb, selfPaste: tracker, log: log)

        #expect(pb.writtenStrings[.string] == "hello world")
        #expect(pb.clearCount == 2) // clearContents() + setString() each increment FakePasteboard.clearCount
        // The changeCount produced by the write must now be suppressed.
        #expect(tracker.shouldSuppress(changeCount: pb.changeCount))
    }

    @Test func pasteSkipsWhenAccessibilityDenied() throws {
        let context = try Self.makeContext()
        let pb = FakePasteboard()
        let key = FakeKeyInjector()
        let log = InMemoryLogSink()
        let item = ClipItem(contentTypeRaw: "text", textContent: "x")
        context.insert(item)

        PasteService.paste(item, context: context,
                           pasteboard: pb,
                           accessibility: FakeAccessibility(isTrusted: false),
                           keyInjector: key, selfPaste: SelfPasteTracker(), log: log)

        #expect(key.pasteCallCount == 0)                 // no injection
        #expect(pb.clearCount == 0)                      // nothing written
        #expect(item.pasteCount == 0)                    // stat unchanged
        #expect(log.events.contains { $0.level == .error })  // logged the denial
    }

    @Test func pasteWritesInjectsAndUpdatesStatsWhenTrusted() throws {
        let context = try Self.makeContext()
        let pb = FakePasteboard()
        let key = FakeKeyInjector()
        let item = ClipItem(contentTypeRaw: "text", textContent: "y")
        context.insert(item)

        PasteService.paste(item, context: context,
                           pasteboard: pb,
                           accessibility: FakeAccessibility(isTrusted: true),
                           keyInjector: key, selfPaste: SelfPasteTracker(), log: InMemoryLogSink())

        #expect(pb.writtenStrings[.string] == "y")
        #expect(key.pasteCallCount == 1)
        #expect(item.pasteCount == 1)
        #expect(item.lastPastedAt != nil)
    }
}
