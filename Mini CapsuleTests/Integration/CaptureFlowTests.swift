import Testing
import Foundation
import SwiftData
import AppKit
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.integration))
struct CaptureFlowTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    private func makeMonitor(pasteboard: FakePasteboard, log: InMemoryLogSink,
                             selfPaste: SelfPasteTracker = SelfPasteTracker()) -> ClipboardMonitor {
        ClipboardMonitor(settings: MockSettingsForSeams(),
                         pasteboard: pasteboard,
                         workspace: FakeWorkspace(bundleID: "com.test.app", appName: "TestApp"),
                         scheduler: FakeScheduler(),
                         selfPaste: selfPaste,
                         log: log)
    }

    @Test func insertsNewText() throws {
        let ctx = try makeContext()
        let pb = FakePasteboard(); pb.stubbedTypes = [.string]; pb.stubbedStrings[.string] = "hello"
        let log = InMemoryLogSink()
        let monitor = makeMonitor(pasteboard: pb, log: log)

        let outcome = monitor.apply(("text", "hello", nil, nil, nil), context: ctx, correlationID: "t1")

        #expect(outcome == .inserted(type: "text"))
        let items = try ctx.fetch(FetchDescriptor<ClipItem>())
        #expect(items.count == 1)
        #expect(items.first?.textContent == "hello")
        #expect(items.first?.sourceAppBundleID == "com.test.app")
        #expect(log.events(in: .store).contains { $0.message.contains("inserted") })
    }

    @Test func dedupsIdenticalText() throws {
        let ctx = try makeContext()
        let monitor = makeMonitor(pasteboard: FakePasteboard(), log: InMemoryLogSink())
        _ = monitor.apply(("text", "dup", nil, nil, nil), context: ctx, correlationID: "a")
        let outcome = monitor.apply(("text", "dup", nil, nil, nil), context: ctx, correlationID: "b")

        #expect(outcome == .dedupedText)
        #expect(try ctx.fetch(FetchDescriptor<ClipItem>()).count == 1)
    }

    @Test func insertsThenDedupsImageByMD5() throws {
        let ctx = try makeContext()
        let monitor = makeMonitor(pasteboard: FakePasteboard(), log: InMemoryLogSink())
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4, 5])

        let first = monitor.apply(("image", nil, png, nil, "a.png"), context: ctx, correlationID: "i1")
        let second = monitor.apply(("image", nil, png, nil, "a.png"), context: ctx, correlationID: "i2")

        #expect(first == .inserted(type: "image"))
        #expect(second == .dedupedImage)
        #expect(try ctx.fetch(FetchDescriptor<ClipItem>()).count == 1)
    }

    @Test func pollOnceSuppressesSelfPastedChange() throws {
        let ctx = try makeContext()
        let pb = FakePasteboard()
        pb.stubbedChangeCount = 4
        pb.stubbedTypes = [.string]; pb.stubbedStrings[.string] = "should not store"
        let tracker = SelfPasteTracker()
        tracker.markRange(begin: 5, end: 5)   // changeCount 5 was self-produced
        let monitor = makeMonitor(pasteboard: pb, log: InMemoryLogSink(), selfPaste: tracker)
        monitor.start(context: ctx)

        pb.stubbedChangeCount = 5             // pasteboard advances to our own value
        monitor.pollOnce()                    // shouldSuppress(5) == true

        #expect(try ctx.fetch(FetchDescriptor<ClipItem>()).isEmpty)   // suppressed, nothing stored
    }

    @Test func enforcesCapWhenInsertingOverLimit() throws {
        let ctx = try makeContext()
        // MockSettingsForSeams.historyMaxCount == 200; pre-populate to the cap.
        for i in 0..<200 {
            ctx.insert(ClipItem(pasteCount: i, contentTypeRaw: "text", textContent: "t\(i)"))
        }
        try ctx.save()
        let monitor = makeMonitor(pasteboard: FakePasteboard(), log: InMemoryLogSink())

        _ = monitor.apply(("text", "new", nil, nil, nil), context: ctx, correlationID: "cap")

        let items = try ctx.fetch(FetchDescriptor<ClipItem>())
        #expect(items.count <= 200)                       // cap respected
        #expect(items.contains { $0.textContent == "new" })
    }

    @Test func archivesChainForDebugging() throws {
        // Demonstrates the full-chain artifact: replay events into LogArchive.
        let ctx = try makeContext()
        let log = InMemoryLogSink()
        let monitor = makeMonitor(pasteboard: FakePasteboard(), log: log)
        _ = monitor.apply(("text", "chain", nil, nil, nil), context: ctx, correlationID: "z9")
        LogArchive.write(log.events, testID: "CaptureFlowTests/archivesChainForDebugging")
        #expect(log.events.contains { $0.correlationID == "z9" })
    }
}
