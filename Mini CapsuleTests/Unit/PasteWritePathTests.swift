import Testing
import Foundation
import SwiftData
import AppKit
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.unit))
struct PasteWritePathTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test func copyImageWritesPNGData() {
        let pb = FakePasteboard()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 9, 9])
        let item = ClipItem(contentTypeRaw: "image", imageData: png)
        PasteService.copyToClipboard(item, pasteboard: pb, selfPaste: SelfPasteTracker(), log: InMemoryLogSink())
        #expect(pb.writtenData[.png] == png)
    }

    @Test func copyTextWithNilContentWritesEmptyString() {
        let pb = FakePasteboard()
        let item = ClipItem(contentTypeRaw: "text", textContent: nil)
        PasteService.copyToClipboard(item, pasteboard: pb, selfPaste: SelfPasteTracker(), log: InMemoryLogSink())
        #expect(pb.writtenStrings[.string] == "")
    }

    @Test func copyUnknownTypeWritesNothingButStillClears() {
        let pb = FakePasteboard()
        let item = ClipItem(contentTypeRaw: "mystery")
        PasteService.copyToClipboard(item, pasteboard: pb, selfPaste: SelfPasteTracker(), log: InMemoryLogSink())
        #expect(pb.clearCount == 1)
        #expect(pb.writtenStrings.isEmpty)
        #expect(pb.writtenData.isEmpty)
    }

    @Test func pasteImageInjectsAndSuppresses() throws {
        let ctx = try makeContext()
        let pb = FakePasteboard()
        let key = FakeKeyInjector()
        let tracker = SelfPasteTracker()
        let item = ClipItem(contentTypeRaw: "image", imageData: Data([1, 2, 3]))
        ctx.insert(item)
        PasteService.paste(item, context: ctx, pasteboard: pb,
                           accessibility: FakeAccessibility(isTrusted: true),
                           keyInjector: key, selfPaste: tracker, log: InMemoryLogSink())
        #expect(pb.writtenData[.png] == Data([1, 2, 3]))
        #expect(key.pasteCallCount == 1)
        #expect(tracker.shouldSuppress(changeCount: pb.changeCount))
    }

    /// Privacy: clipboard CONTENT must never appear in log metadata/messages.
    @Test func loggingNeverLeaksClipboardContent() throws {
        let ctx = try makeContext()
        let log = InMemoryLogSink()
        let monitor = ClipboardMonitor(settings: MockSettingsForSeams(),
                                       pasteboard: FakePasteboard(),
                                       workspace: FakeWorkspace(bundleID: "x", appName: "X"),
                                       scheduler: FakeScheduler(), selfPaste: SelfPasteTracker(), log: log)
        let secret = "SUPER-SECRET-TOKEN-abc123"
        _ = monitor.apply(("text", secret, nil, nil, nil), context: ctx, correlationID: "p1")

        for event in log.events {
            #expect(!event.message.contains(secret), "content leaked into message")
            for (_, value) in event.metadata {
                #expect(!value.contains(secret), "content leaked into metadata")
            }
        }
    }
}
