import Testing
import Foundation
import AppKit
import SwiftData
@testable import Mini_Capsule

@Suite(.tags(.integration))
struct PasteboardSeamTests {
    @Test func nsPasteboardConformsToReadingAndWriting() {
        let pb: PasteboardReading & PasteboardWriting = NSPasteboard.withUniqueName()
        pb.clearContents()
        _ = pb.setString("hi", forType: .string)
        #expect(pb.string(forType: .string) == "hi")
        #expect(pb.changeCount >= 1)
    }

    @Test func fakePasteboardRecordsWritesAndServesReads() {
        let fake = FakePasteboard()
        fake.stubbedTypes = [.string]
        fake.stubbedStrings[.string] = "hello"
        #expect(fake.string(forType: .string) == "hello")
        #expect(fake.types == [.string])
        _ = fake.setData(Data([1, 2, 3]), forType: .png)
        #expect(fake.writtenData[.png] == Data([1, 2, 3]))
        #expect(fake.clearCount == 1)
    }
}

@Suite(.tags(.integration))
struct SystemSeamTests {
    @Test func fakeWorkspaceReturnsStubbedIdentity() {
        let ws = FakeWorkspace(bundleID: "com.apple.Safari", appName: "Safari")
        #expect(ws.bundleID == "com.apple.Safari")
        #expect(ws.appName == "Safari")
    }

    @Test func fakeAccessibilityHonorsTrustFlag() {
        #expect(FakeAccessibility(isTrusted: true).isTrusted)
        #expect(!FakeAccessibility(isTrusted: false).isTrusted)
    }

    @Test func fakeKeyInjectorRecordsCalls() {
        let k = FakeKeyInjector()
        k.pasteViaCommandV()
        k.pasteViaCommandV()
        #expect(k.pasteCallCount == 2)
    }
}

@Suite(.tags(.integration))
struct SelfPasteTrackerTests {
    @Test func suppressesMarkedRangeExactlyOnce() {
        let t = SelfPasteTracker(maxEntries: 200)
        t.markRange(begin: 10, end: 12)
        #expect(t.shouldSuppress(changeCount: 11))          // in range
        #expect(!t.shouldSuppress(changeCount: 11))         // consumed once
        #expect(t.shouldSuppress(changeCount: 10))          // boundary low
        #expect(t.shouldSuppress(changeCount: 12))          // boundary high
        #expect(!t.shouldSuppress(changeCount: 13))         // outside
    }

    @Test func resetsWhenOverCapacity() {
        let t = SelfPasteTracker(maxEntries: 5)
        t.markRange(begin: 0, end: 100)   // 101 entries > 5 → cleared
        #expect(!t.shouldSuppress(changeCount: 50))
    }
}

// MARK: - MonitorConstructionTests

/// Minimal settings stub for construction (full flow uses the shared MockSettings in Task 7).
final class MockSettingsForSeams: SettingsProtocol {
    var historyMaxCount = 200; var imageMaxSizeMB = 2; var pollingInterval = 0.5
    var cleanupOnStartup = true; var dedupEnabled = true
    var showHideShortcut = ""; var quickPasteShortcut = ""; var togglePinShortcut = ""
    var iCloudSyncEnabled = false; var launchAtLogin = false
    var showInMenuBar = true; var showFloatingPanel = true
    var collapsedStyle = "capsule"; var hoverExpandDelay = 0.3; var hoverCollapseDelay = 1.0
    var panelOpacityUnfocused = 0.6; var backgroundImageData = Data(); var ringDiameter = 30.0
    var capsuleWindowFrame = Data()
    func resetAll() {}
    func exportData(context: ModelContext) -> Data? { nil }
    func importData(_ data: Data, context: ModelContext) throws {}
    func clearAllHistory(context: ModelContext) {}
}

@MainActor
@Suite(.tags(.integration))
struct MonitorConstructionTests {
    @Test func monitorAcceptsInjectedSeams() {
        let m = ClipboardMonitor(settings: MockSettingsForSeams(),
                                 pasteboard: FakePasteboard(),
                                 workspace: FakeWorkspace(bundleID: "x", appName: "X"),
                                 scheduler: FakeScheduler(),
                                 selfPaste: SelfPasteTracker(),
                                 log: InMemoryLogSink())
        #expect(m.context == nil)   // not started yet
    }
}
