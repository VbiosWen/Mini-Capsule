# Seams & Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `ClipboardMonitor`, `PasteService`, and `HotKeyCenter` behind protocol seams (injected with production defaults) so their logic runs headless and deterministically, wire structured logging into them, and add T2 integration tests for the capture flow and hotkey dispatch.

**Architecture:** Every system boundary becomes a protocol whose production conformance points at the real singleton, supplied as a default parameter — so existing call sites compile and behave identically. Pasteboard suppression moves out of static `PasteService` state into an injectable `SelfPasteTracker`. `ClipboardMonitor.checkPasteboard()` is split into a thin `pollOnce()` + a store-coupled `apply(content:) -> CaptureOutcome` that returns an assertable value and logs each step. `HotKeyCenter` delegates Carbon registration to a `HotKeyRegistering` seam.

**Tech Stack:** Swift Testing, `os.Logger` (via the Plan 1 `Log` façade), `AppKit`/`NSPasteboard`/`NSWorkspace`, Carbon `RegisterEventHotKey`, SwiftData in-memory `ModelContainer`.

## Global Constraints

- **Prerequisite:** Plan 1 (`2026-07-12-test-foundation-logging-plan.md`) is landed — `LogEvent`, `LogSink`, `Log`, `InMemoryLogSink`, `LogArchive`, `@Tag`s, `MiniCapsule.xctestplan`, `Scripts/run-tests.sh`, and the coverage manifest all exist.
- **Deployment floor:** macOS 14.0. Xcode synchronized groups — no `project.pbxproj` edits for new files.
- **Behavior preservation (critical):** this is a refactor. Runtime behavior must be identical. The pre-existing 104 tests **plus** the Plan 1 tests must stay green after every task. Production-default parameters guarantee unchanged call sites.
- **Privacy rule:** never log clipboard content — only counts/types/ids/md5-prefixes.
- **Test module import:** `@testable import Mini_Capsule`.
- **No new third-party dependencies.**
- **Full xcodebuild path** if needed: `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild`.

---

## File Structure

**New app files (target: Mini Capsule):**
- `Mini Capsule/Services/Seams/PasteboardSeams.swift` — `PasteboardReading`, `PasteboardWriting` + `NSPasteboard` conformances
- `Mini Capsule/Services/Seams/SystemSeams.swift` — `FrontmostAppProviding`, `AccessibilityChecking`, `KeyInjecting` + production conformances
- `Mini Capsule/Services/Seams/Scheduling.swift` — `Scheduling`, `Cancellable`, `RealScheduler`
- `Mini Capsule/Services/Seams/HotKeyRegistering.swift` — `HotKeyRegistering` + `CarbonHotKeyRegistrar`
- `Mini Capsule/Services/SelfPasteTracker.swift` — extracted suppression set

**New test files (target: Mini CapsuleTests):**
- `Mini CapsuleTests/Support/Fakes.swift` — `FakePasteboard`, `FakeWorkspace`, `FakeScheduler`, `FakeAccessibility`, `FakeKeyInjector`, `FakeHotKeyRegistrar`
- `Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift`
- `Mini CapsuleTests/Integration/HotKeyCenterIntegrationTests.swift`
- `Mini CapsuleTests/Integration/CaptureFlowTests.swift`

**Modified app files:**
- `Mini Capsule/Services/PasteService.swift` — inject seams + `SelfPasteTracker`, add logging
- `Mini Capsule/Services/ClipboardMonitor.swift` — inject seams, decompose `checkPasteboard`, add logging, make `readPasteboard`/`apply` internal
- `Mini Capsule/Services/HotKeyCenter.swift` — delegate to `HotKeyRegistering`

**Modified infra:**
- `docs/testing/coverage-manifest.json` — features 1 & 7 → `covered`
- `docs/testing/traceability-matrix.md` — mirror the manifest change

---

## Task 1: Pasteboard seams

**Files:**
- Create: `Mini Capsule/Services/Seams/PasteboardSeams.swift`
- Create: `Mini CapsuleTests/Support/Fakes.swift` (start with `FakePasteboard`)
- Create: `Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift` (placeholder suite used to host the first seam test)

**Interfaces:**
- Produces:
  - `protocol PasteboardReading: AnyObject { var changeCount: Int { get }; var types: [NSPasteboard.PasteboardType]? { get }; func data(forType: NSPasteboard.PasteboardType) -> Data?; func string(forType: NSPasteboard.PasteboardType) -> String?; func propertyList(forType: NSPasteboard.PasteboardType) -> Any?; func readObjects(forClasses: [AnyClass], options: [NSPasteboard.ReadingOptionKey: Any]?) -> [Any]? }`
  - `protocol PasteboardWriting: AnyObject { var changeCount: Int { get }; @discardableResult func clearContents() -> Int; @discardableResult func setString(_: String, forType: NSPasteboard.PasteboardType) -> Bool; @discardableResult func setData(_: Data, forType: NSPasteboard.PasteboardType) -> Bool; @discardableResult func setPropertyList(_: Any, forType: NSPasteboard.PasteboardType) -> Bool; @discardableResult func writeObjects(_: [NSPasteboardWriting]) -> Bool }`
  - `extension NSPasteboard: PasteboardReading, PasteboardWriting {}`
  - Test fake: `final class FakePasteboard: PasteboardReading, PasteboardWriting` (see step 3).

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift`:

```swift
import Testing
import Foundation
import AppKit
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/PasteboardSeamTests" 2>&1 | tail -20`
Expected: FAIL — `cannot find type 'PasteboardReading' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Mini Capsule/Services/Seams/PasteboardSeams.swift`:

```swift
import AppKit

/// Read side of NSPasteboard, injectable for tests.
protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func propertyList(forType type: NSPasteboard.PasteboardType) -> Any?
    func readObjects(forClasses classArray: [AnyClass],
                     options: [NSPasteboard.ReadingOptionKey: Any]?) -> [Any]?
}

/// Write side of NSPasteboard, injectable for tests.
protocol PasteboardWriting: AnyObject {
    var changeCount: Int { get }
    @discardableResult func clearContents() -> Int
    @discardableResult func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
    @discardableResult func setData(_ data: Data, forType type: NSPasteboard.PasteboardType) -> Bool
    @discardableResult func setPropertyList(_ plist: Any, forType type: NSPasteboard.PasteboardType) -> Bool
    @discardableResult func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

// NSPasteboard's real signatures already satisfy both protocols.
extension NSPasteboard: PasteboardReading, PasteboardWriting {}
```

Create `Mini CapsuleTests/Support/Fakes.swift`:

```swift
import AppKit
@testable import Mini_Capsule

/// In-memory pasteboard for deterministic capture/paste tests.
final class FakePasteboard: PasteboardReading, PasteboardWriting {
    // Read stubs
    var stubbedChangeCount = 1
    var stubbedTypes: [NSPasteboard.PasteboardType]? = nil
    var stubbedStrings: [NSPasteboard.PasteboardType: String] = [:]
    var stubbedData: [NSPasteboard.PasteboardType: Data] = [:]
    var stubbedPropertyLists: [NSPasteboard.PasteboardType: Any] = [:]
    var stubbedReadObjects: [Any] = []

    // Write recordings
    private(set) var clearCount = 0
    private(set) var writtenStrings: [NSPasteboard.PasteboardType: String] = [:]
    private(set) var writtenData: [NSPasteboard.PasteboardType: Data] = [:]
    private(set) var writtenPropertyLists: [NSPasteboard.PasteboardType: Any] = [:]
    private(set) var writtenObjectCount = 0

    var changeCount: Int { stubbedChangeCount }
    var types: [NSPasteboard.PasteboardType]? { stubbedTypes }
    func data(forType type: NSPasteboard.PasteboardType) -> Data? { stubbedData[type] }
    func string(forType type: NSPasteboard.PasteboardType) -> String? { stubbedStrings[type] }
    func propertyList(forType type: NSPasteboard.PasteboardType) -> Any? { stubbedPropertyLists[type] }
    func readObjects(forClasses classArray: [AnyClass],
                     options: [NSPasteboard.ReadingOptionKey: Any]?) -> [Any]? {
        stubbedReadObjects.isEmpty ? nil : stubbedReadObjects
    }

    @discardableResult func clearContents() -> Int { clearCount += 1; stubbedChangeCount += 1; return stubbedChangeCount }
    @discardableResult func setString(_ s: String, forType t: NSPasteboard.PasteboardType) -> Bool { writtenStrings[t] = s; stubbedChangeCount += 1; return true }
    @discardableResult func setData(_ d: Data, forType t: NSPasteboard.PasteboardType) -> Bool { writtenData[t] = d; stubbedChangeCount += 1; return true }
    @discardableResult func setPropertyList(_ p: Any, forType t: NSPasteboard.PasteboardType) -> Bool { writtenPropertyLists[t] = p; stubbedChangeCount += 1; return true }
    @discardableResult func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool { writtenObjectCount += objects.count; stubbedChangeCount += 1; return true }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/PasteboardSeamTests" 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Services/Seams/PasteboardSeams.swift" "Mini CapsuleTests/Support/Fakes.swift" "Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift"
git commit -m "feat(seams): add PasteboardReading/Writing protocols + FakePasteboard"
```

---

## Task 2: System seams (frontmost app, accessibility, key injection)

**Files:**
- Create: `Mini Capsule/Services/Seams/SystemSeams.swift`
- Modify: `Mini CapsuleTests/Support/Fakes.swift` (add `FakeWorkspace`, `FakeAccessibility`, `FakeKeyInjector`)
- Modify: `Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift` (add a system-seams test suite)

**Interfaces:**
- Produces:
  - `protocol FrontmostAppProviding { var bundleID: String? { get }; var appName: String? { get } }` + `struct RealFrontmostApp: FrontmostAppProviding`
  - `protocol AccessibilityChecking { var isTrusted: Bool { get } }` + `struct RealAccessibility: AccessibilityChecking`
  - `protocol KeyInjecting { func pasteViaCommandV() }` + `struct RealKeyInjector: KeyInjecting`
  - Fakes: `FakeWorkspace`, `FakeAccessibility(isTrusted:)`, `FakeKeyInjector` (records `pasteCallCount`).

- [ ] **Step 1: Write the failing test**

Append to `Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/SystemSeamTests" 2>&1 | tail -20`
Expected: FAIL — `cannot find 'FakeWorkspace' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Mini Capsule/Services/Seams/SystemSeams.swift`:

```swift
import AppKit
import ApplicationServices
import CoreGraphics

/// Identity of the frontmost application (source app for a capture).
protocol FrontmostAppProviding {
    var bundleID: String? { get }
    var appName: String? { get }
}

struct RealFrontmostApp: FrontmostAppProviding {
    var bundleID: String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    var appName: String? { NSWorkspace.shared.frontmostApplication?.localizedName }
}

/// Whether the process is trusted for Accessibility (needed to inject keystrokes).
protocol AccessibilityChecking {
    var isTrusted: Bool { get }
}

struct RealAccessibility: AccessibilityChecking {
    var isTrusted: Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }
}

/// Injects a synthetic Cmd+V. Production posts CGEvents; tests record the call.
protocol KeyInjecting {
    func pasteViaCommandV()
}

struct RealKeyInjector: KeyInjecting {
    func pasteViaCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdKey: CGKeyCode = 0x37
        let vKey: CGKeyCode = PasteService.keyCodeForV()

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)

        let cmdFlag = CGEventFlags.maskCommand.rawValue
        cmdDown?.flags = CGEventFlags(rawValue: cmdFlag)
        vDown?.flags = CGEventFlags(rawValue: cmdFlag)
        vUp?.flags = CGEventFlags(rawValue: cmdFlag)
        cmdUp?.flags = CGEventFlags(rawValue: 0)

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
}
```

Append to `Mini CapsuleTests/Support/Fakes.swift`:

```swift
struct FakeWorkspace: FrontmostAppProviding {
    var bundleID: String?
    var appName: String?
}

struct FakeAccessibility: AccessibilityChecking {
    let isTrusted: Bool
}

final class FakeKeyInjector: KeyInjecting {
    private(set) var pasteCallCount = 0
    func pasteViaCommandV() { pasteCallCount += 1 }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/SystemSeamTests" 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Services/Seams/SystemSeams.swift" "Mini CapsuleTests/Support/Fakes.swift" "Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift"
git commit -m "feat(seams): add frontmost-app, accessibility, key-injection seams + fakes"
```

---

## Task 3: `SelfPasteTracker` extraction

**Files:**
- Create: `Mini Capsule/Services/SelfPasteTracker.swift`
- Modify: `Mini Capsule/Services/PasteService.swift` (delegate suppression to the tracker)
- Modify: `Mini Capsule/Services/ClipboardMonitor.swift:104` (use injected tracker — full injection lands in Task 6; here just swap the static call to `SelfPasteTracker.shared`)
- Rewrite: `Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift` (add the tracker suite; keep the seam suites already there)

**Interfaces:**
- Produces: `final class SelfPasteTracker: @unchecked Sendable` with `static let shared`, `init(maxEntries: Int = 200)`, `func markRange(begin: Int, end: Int)`, `func shouldSuppress(changeCount: Int) -> Bool`, `func reset()`.
- Consumes: nothing new.

- [ ] **Step 1: Write the failing test**

Add to `Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift` (top-level, alongside the existing suites):

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/SelfPasteTrackerTests" 2>&1 | tail -20`
Expected: FAIL — `cannot find 'SelfPasteTracker' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Mini Capsule/Services/SelfPasteTracker.swift`:

```swift
import Foundation

/// Tracks the changeCount values produced by our own copy/paste so the monitor
/// can skip re-capturing them. Extracted from PasteService's former static set.
/// Thread-safe; a `.shared` instance is used in production.
final class SelfPasteTracker: @unchecked Sendable {
    static let shared = SelfPasteTracker()

    private let lock = NSLock()
    private var suppressed = Set<Int>()
    private let maxEntries: Int

    init(maxEntries: Int = 200) { self.maxEntries = maxEntries }

    /// Mark the inclusive range [begin, end] as self-produced.
    func markRange(begin: Int, end: Int) {
        guard begin <= end else { return }
        lock.withLock {
            suppressed.formUnion(begin...end)
            if suppressed.count > maxEntries { suppressed.removeAll() }
        }
    }

    /// Returns true and consumes the value when `changeCount` was self-produced.
    func shouldSuppress(changeCount: Int) -> Bool {
        lock.withLock {
            if suppressed.contains(changeCount) {
                suppressed.remove(changeCount)
                return true
            }
            return false
        }
    }

    func reset() { lock.withLock { suppressed.removeAll() } }
}
```

Modify `Mini Capsule/Services/PasteService.swift` — replace the static suppression block (the `suppressedChangeCounts` property and `beginSelfPaste`/`endSelfPaste`/`shouldSuppress` methods, lines ~10–44) with delegators to the tracker:

```swift
    // Suppression state now lives in SelfPasteTracker (injectable, testable).
    static func beginSelfPaste() -> Int { NSPasteboard.general.changeCount }

    static func endSelfPaste(begin: Int) {
        let end = NSPasteboard.general.changeCount
        SelfPasteTracker.shared.markRange(begin: begin, end: end)
    }

    static func shouldSuppress(changeCount: Int) -> Bool {
        SelfPasteTracker.shared.shouldSuppress(changeCount: changeCount)
    }
```

Modify `Mini Capsule/Services/ClipboardMonitor.swift:104` — leave as `PasteService.shouldSuppress(changeCount:)` for now (it delegates to the tracker); full injection lands in Task 6. **No change needed this task** beyond confirming it still compiles.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/SelfPasteTrackerTests" 2>&1 | tail -20`
Then confirm no regression in the existing paste suppression tests:
Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/PasteServiceTests" 2>&1 | tail -20`
Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Services/SelfPasteTracker.swift" "Mini Capsule/Services/PasteService.swift" "Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift"
git commit -m "refactor(paste): extract SelfPasteTracker from PasteService static state"
```

---

## Task 4: Inject seams into `PasteService.copyToClipboard`/`paste` + logging

**Files:**
- Modify: `Mini Capsule/Services/PasteService.swift`
- Create: `Mini CapsuleTests/Integration/PasteServiceSeamTests.swift`

**Interfaces:**
- Consumes: `PasteboardWriting`, `AccessibilityChecking`, `KeyInjecting`, `SelfPasteTracker`, `LogSink`.
- Produces (updated signatures, all with production defaults — call sites unchanged):
  - `static func copyToClipboard(_ item: ClipItem, pasteboard: PasteboardWriting = NSPasteboard.general, selfPaste: SelfPasteTracker = .shared, log: LogSink = Log.shared)`
  - `static func paste(_ item: ClipItem, context: ModelContext, pasteboard: PasteboardWriting = NSPasteboard.general, accessibility: AccessibilityChecking = RealAccessibility(), keyInjector: KeyInjecting = RealKeyInjector(), selfPaste: SelfPasteTracker = .shared, log: LogSink = Log.shared)`

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/Integration/PasteServiceSeamTests.swift`:

```swift
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
        #expect(pb.clearCount == 1)
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/PasteServiceSeamTests" 2>&1 | tail -20`
Expected: FAIL — extra-argument errors (`pasteboard:` etc. not yet accepted).

- [ ] **Step 3: Write minimal implementation**

In `Mini Capsule/Services/PasteService.swift`, replace `copyToClipboard` and `paste` with the seam-injected versions. Also change `writeFileItemsToPasteboard` to take `PasteboardWriting`:

```swift
    private static func writeFileItemsToPasteboard(_ item: ClipItem, pasteboard: PasteboardWriting) {
        guard let bookmarkData = item.fileBookmarks else { return }
        let bookmarks = Self.decodeFileBookmarks(bookmarkData)
        var isStale = false
        let urls: [URL] = bookmarks.compactMap {
            try? URL(resolvingBookmarkData: $0, options: [], bookmarkDataIsStale: &isStale)
        }
        guard !urls.isEmpty else { return }
        pasteboard.setPropertyList(urls.map { $0.path },
                                   forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        let pbItems: [NSPasteboardItem] = urls.map { url in
            let pbItem = NSPasteboardItem()
            pbItem.setString(url.absoluteString, forType: .fileURL)
            return pbItem
        }
        pasteboard.writeObjects(pbItems)
    }

    static func copyToClipboard(_ item: ClipItem,
                                pasteboard: PasteboardWriting = NSPasteboard.general,
                                selfPaste: SelfPasteTracker = .shared,
                                log: LogSink = Log.shared) {
        let begin = pasteboard.changeCount
        pasteboard.clearContents()
        switch item.contentTypeRaw {
        case "text":  pasteboard.setString(item.textContent ?? "", forType: .string)
        case "image": if let data = item.imageData { pasteboard.setData(data, forType: .png) }
        case "file":  writeFileItemsToPasteboard(item, pasteboard: pasteboard)
        default: break
        }
        let end = pasteboard.changeCount
        selfPaste.markRange(begin: begin, end: end)
        log.log(.paste, .info, "copyToClipboard", metadata: ["type": item.contentTypeRaw])
    }

    static func paste(_ item: ClipItem,
                      context: ModelContext,
                      pasteboard: PasteboardWriting = NSPasteboard.general,
                      accessibility: AccessibilityChecking = RealAccessibility(),
                      keyInjector: KeyInjecting = RealKeyInjector(),
                      selfPaste: SelfPasteTracker = .shared,
                      log: LogSink = Log.shared) {
        guard accessibility.isTrusted else {
            log.log(.paste, .error, "paste skipped: accessibility not trusted",
                    metadata: ["type": item.contentTypeRaw])
            return
        }
        let begin = pasteboard.changeCount
        pasteboard.clearContents()
        switch item.contentTypeRaw {
        case "text":  pasteboard.setString(item.textContent ?? "", forType: .string)
        case "image": if let data = item.imageData { pasteboard.setData(data, forType: .png) }
        case "file":  writeFileItemsToPasteboard(item, pasteboard: pasteboard)
        default: break
        }
        let end = pasteboard.changeCount
        selfPaste.markRange(begin: begin, end: end)

        keyInjector.pasteViaCommandV()

        item.pasteCount += 1
        item.lastPastedAt = Date()
        do { try context.save() }
        catch { log.log(.paste, .error, "paste stat save failed", metadata: ["error": "\(error)"]) }
        log.log(.paste, .info, "paste", metadata: ["type": item.contentTypeRaw, "count": "\(item.pasteCount)"])
    }
```

Delete the old CGEvent code block that previously lived inside `paste` (it now lives in `RealKeyInjector`). Keep `keyCodeForV()`, `decodeFileBookmarks`, `beginSelfPaste`, `endSelfPaste`, `shouldSuppress` as-is.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/PasteServiceSeamTests" 2>&1 | tail -20`
Then regression-check callers compile & pass:
Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/PasteServiceTests" 2>&1 | tail -20`
Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Services/PasteService.swift" "Mini CapsuleTests/Integration/PasteServiceSeamTests.swift"
git commit -m "refactor(paste): inject pasteboard/accessibility/key-injection seams + logging"
```

---

## Task 5: `Scheduling` seam + `HotKeyRegistering` seam + `HotKeyCenter` refactor

**Files:**
- Create: `Mini Capsule/Services/Seams/Scheduling.swift`
- Create: `Mini Capsule/Services/Seams/HotKeyRegistering.swift`
- Modify: `Mini Capsule/Services/HotKeyCenter.swift`
- Modify: `Mini CapsuleTests/Support/Fakes.swift` (add `FakeScheduler`, `FakeHotKeyRegistrar`)
- Create: `Mini CapsuleTests/Integration/HotKeyCenterIntegrationTests.swift`

**Interfaces:**
- Produces:
  - `protocol Cancellable: AnyObject { func cancel() }`
  - `protocol Scheduling: AnyObject { @discardableResult func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable; @discardableResult func every(_ interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable }` + `final class RealScheduler: Scheduling`
  - `protocol HotKeyRegistering: AnyObject { func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool; func unregisterAll() }` + `final class CarbonHotKeyRegistrar: HotKeyRegistering`
  - `HotKeyCenter.init(registrar: HotKeyRegistering = CarbonHotKeyRegistrar())`, with `register(_ shortcut:action:)`, `unregisterAll()`, `installHandlerIfNeeded()` unchanged in signature.
  - Fakes: `FakeScheduler` (fires pending blocks on demand), `FakeHotKeyRegistrar` (records registrations, `simulateFire(keyCode:modifiers:)`).

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/Integration/HotKeyCenterIntegrationTests.swift`:

```swift
import Testing
import AppKit
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.integration))
struct HotKeyCenterIntegrationTests {
    @Test func registerParsesShortcutAndForwardsKeyCodeModifiers() {
        let registrar = FakeHotKeyRegistrar()
        let center = HotKeyCenter(registrar: registrar)
        var fired = false
        center.register("cmd+shift+v") { fired = true }

        let entry = registrar.registrations.first
        #expect(entry != nil)
        // 'v' key code from HotKeyParser + cmd|shift modifiers.
        let expected = HotKeyParser.parse("cmd+shift+v")
        #expect(entry?.keyCode == expected?.keyCode)
        #expect(entry?.modifiers == expected?.modifiers)

        registrar.simulateFire(keyCode: entry!.keyCode, modifiers: entry!.modifiers)
        #expect(fired)
    }

    @Test func invalidShortcutRegistersNothing() {
        let registrar = FakeHotKeyRegistrar()
        let center = HotKeyCenter(registrar: registrar)
        center.register("cmd+shift") { }   // no non-modifier key → parse nil
        #expect(registrar.registrations.isEmpty)
    }

    @Test func unregisterAllClearsRegistrar() {
        let registrar = FakeHotKeyRegistrar()
        let center = HotKeyCenter(registrar: registrar)
        center.register("cmd+c") { }
        center.unregisterAll()
        #expect(registrar.unregisterAllCount == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/HotKeyCenterIntegrationTests" 2>&1 | tail -20`
Expected: FAIL — `argument passed to call that takes no arguments` (HotKeyCenter has no `registrar:` init).

- [ ] **Step 3: Write minimal implementation**

Create `Mini Capsule/Services/Seams/Scheduling.swift`:

```swift
import Foundation

protocol Cancellable: AnyObject { func cancel() }

/// Timer/dispatch abstraction so burst/poll timing is deterministic in tests.
protocol Scheduling: AnyObject {
    @discardableResult func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable
    @discardableResult func every(_ interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable
}

final class RealScheduler: Scheduling {
    private final class TimerToken: Cancellable {
        let timer: Timer
        init(_ timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }
    private final class WorkToken: Cancellable {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    @discardableResult func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let item = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return WorkToken(item)
    }

    @discardableResult func every(_ interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in block() }
        return TimerToken(timer)
    }
}
```

Create `Mini Capsule/Services/Seams/HotKeyRegistering.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys. Production wraps Carbon RegisterEventHotKey.
protocol HotKeyRegistering: AnyObject {
    @discardableResult func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool
    func unregisterAll()
}

/// Production Carbon registrar — the former guts of HotKeyCenter live here.
@MainActor
final class CarbonHotKeyRegistrar: HotKeyRegistering {
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private static let signature: OSType = 0x4D435053 // 'MCPS'

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let this = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { registrar.actions[hkID.id]?() }
            return noErr
        }, 1, &spec, this, &handler)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID; nextID += 1
        let hkID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref); actions[id] = handler; return true }
        return false
    }

    func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll(); actions.removeAll()
    }

    deinit {
        for ref in refs { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
```

Replace `Mini Capsule/Services/HotKeyCenter.swift`'s `HotKeyCenter` class (keep the `HotKeyParser` enum above it untouched) with a thin coordinator:

```swift
/// Parses shortcuts and delegates registration to a HotKeyRegistering seam.
@MainActor
final class HotKeyCenter {
    private let registrar: HotKeyRegistering

    init(registrar: HotKeyRegistering = CarbonHotKeyRegistrar()) {
        self.registrar = registrar
    }

    /// Retained for existing call sites; the registrar installs its handler lazily.
    func installHandlerIfNeeded() { /* registrar installs on first register */ }

    func register(_ shortcut: String, action: @escaping () -> Void) {
        guard let (keyCode, modifiers) = HotKeyParser.parse(shortcut) else { return }
        registrar.register(keyCode: keyCode, modifiers: modifiers, handler: action)
    }

    func unregisterAll() { registrar.unregisterAll() }
}
```

Append to `Mini CapsuleTests/Support/Fakes.swift`:

```swift
import Foundation

final class FakeScheduler: Scheduling {
    final class Token: Cancellable {
        var cancelled = false
        func cancel() { cancelled = true }
    }
    struct Pending { let token: Token; let block: () -> Void }
    private(set) var afterBlocks: [Pending] = []
    private(set) var everyBlocks: [Pending] = []

    @discardableResult func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let t = Token(); afterBlocks.append(Pending(token: t, block: block)); return t
    }
    @discardableResult func every(_ interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let t = Token(); everyBlocks.append(Pending(token: t, block: block)); return t
    }
    /// Fire all non-cancelled one-shot blocks (simulates the delay elapsing).
    func fireAfter() { afterBlocks.filter { !$0.token.cancelled }.forEach { $0.block() } }
    /// Fire one tick of every repeating block.
    func tick() { everyBlocks.filter { !$0.token.cancelled }.forEach { $0.block() } }
}

@MainActor
final class FakeHotKeyRegistrar: HotKeyRegistering {
    struct Registration { let keyCode: UInt32; let modifiers: UInt32; let handler: () -> Void }
    private(set) var registrations: [Registration] = []
    private(set) var unregisterAllCount = 0

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        registrations.append(Registration(keyCode: keyCode, modifiers: modifiers, handler: handler))
        return true
    }
    func unregisterAll() { unregisterAllCount += 1; registrations.removeAll() }

    /// Test helper: invoke the handler registered for this key/modifier combo.
    func simulateFire(keyCode: UInt32, modifiers: UInt32) {
        registrations.first { $0.keyCode == keyCode && $0.modifiers == modifiers }?.handler()
    }
}
```

> **Note on `Mini_CapsuleApp.swift`:** `HotKeyCenter()` (line 26) still compiles — the new `init` has a default registrar. `installHandlerIfNeeded()`, `register(_:action:)`, `unregisterAll()` keep their signatures, so lines 110–119 are unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/HotKeyCenterIntegrationTests" 2>&1 | tail -20`
Then confirm the existing parser tests still pass:
Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/HotKeyParserTests" 2>&1 | tail -20`
Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Services/Seams/Scheduling.swift" "Mini Capsule/Services/Seams/HotKeyRegistering.swift" "Mini Capsule/Services/HotKeyCenter.swift" "Mini CapsuleTests/Support/Fakes.swift" "Mini CapsuleTests/Integration/HotKeyCenterIntegrationTests.swift"
git commit -m "refactor(hotkey): extract HotKeyRegistering + Scheduling seams; thin HotKeyCenter"
```

---

## Task 6: Refactor `ClipboardMonitor` — inject seams, decompose, log

**Files:**
- Modify: `Mini Capsule/Services/ClipboardMonitor.swift`

**Interfaces:**
- Consumes: `PasteboardReading`, `FrontmostAppProviding`, `Scheduling`, `Cancellable`, `SelfPasteTracker`, `LogSink`.
- Produces:
  - `init(settings: SettingsProtocol, pasteboard: PasteboardReading = NSPasteboard.general, workspace: FrontmostAppProviding = RealFrontmostApp(), scheduler: Scheduling = RealScheduler(), selfPaste: SelfPasteTracker = .shared, log: LogSink = Log.shared)`
  - `enum CaptureOutcome: Equatable { case skipped, dedupedText, dedupedImage, inserted(type: String) }`
  - `func pollOnce()` (internal; the former `checkPasteboard` body)
  - `@discardableResult func apply(_ content: (type: String, text: String?, image: Data?, fileBookmarks: Data?, fileName: String?), context: ModelContext, correlationID: String) -> CaptureOutcome` (internal)
  - `readPasteboard(_:types:)` becomes `internal` and takes `PasteboardReading`.

**This task preserves behavior.** It is a structural refactor: same branching, plus logging and a returned outcome.

- [ ] **Step 1: Write the failing test**

Add to a new file is unnecessary — this task's behavior is covered by Task 7's `CaptureFlowTests`. To keep TDD honest, add one focused test now to `Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/MonitorConstructionTests" 2>&1 | tail -20`
Expected: FAIL — extra arguments in the `ClipboardMonitor` initializer.

- [ ] **Step 3: Write minimal implementation**

In `Mini Capsule/Services/ClipboardMonitor.swift`:

**(a)** Replace the stored properties and `init` (lines ~8–22) with:

```swift
@MainActor
final class ClipboardMonitor: ObservableObject {
    private let settings: SettingsProtocol
    private let pasteboardSource: PasteboardReading
    private let workspace: FrontmostAppProviding
    private let scheduler: Scheduling
    private let selfPaste: SelfPasteTracker
    private let log: LogSink

    private var timerToken: Cancellable?
    private var lastChangeCount: Int
    private(set) var context: ModelContext?

    private var burstCount = 0
    private var burstToken: Cancellable?

    init(settings: SettingsProtocol,
         pasteboard: PasteboardReading = NSPasteboard.general,
         workspace: FrontmostAppProviding = RealFrontmostApp(),
         scheduler: Scheduling = RealScheduler(),
         selfPaste: SelfPasteTracker = .shared,
         log: LogSink = Log.shared) {
        self.settings = settings
        self.pasteboardSource = pasteboard
        self.workspace = workspace
        self.scheduler = scheduler
        self.selfPaste = selfPaste
        self.log = log
        self.lastChangeCount = pasteboard.changeCount
    }
```

**(b)** Replace `restartTimer`, `scheduleBurstPoll`, `start`, `stop` to use the scheduler:

```swift
    func start(context: ModelContext) {
        self.context = context
        lastChangeCount = pasteboardSource.changeCount
        restartTimer()
        observeSettings()
        log.log(.capture, .info, "monitor started", metadata: ["interval": "\(currentPollingInterval)"])
    }

    private func restartTimer() {
        timerToken?.cancel()
        timerToken = scheduler.every(currentPollingInterval) { [weak self] in
            self?.pollOnce()
        }
    }

    private func scheduleBurstPoll() {
        guard burstCount < 3 else { burstCount = 0; return }
        burstCount += 1
        burstToken?.cancel()
        burstToken = scheduler.after(0.05) { [weak self] in
            self?.pollOnce()
        }
    }

    func stop() {
        timerToken?.cancel(); timerToken = nil
        burstToken?.cancel(); burstToken = nil
        context = nil
    }
```

**(c)** Replace `checkPasteboard()` (the whole method) with `pollOnce()` + `apply(...)`:

```swift
    func pollOnce() {
        guard let context = context else { return }
        let currentChangeCount = pasteboardSource.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        let cid = String(UUID().uuidString.prefix(4))
        log.log(.capture, .debug, "changeCount changed",
                metadata: ["to": "\(currentChangeCount)"], correlationID: cid)

        if selfPaste.shouldSuppress(changeCount: currentChangeCount) {
            log.log(.capture, .debug, "suppressed self-paste", correlationID: cid)
            return
        }

        guard let pbTypes = pasteboardSource.types,
              let content = readPasteboard(pasteboardSource, types: pbTypes) else {
            log.log(.capture, .notice, "no content read", correlationID: cid)
            scheduleBurstPoll()
            return
        }

        _ = apply(content, context: context, correlationID: cid)
        scheduleBurstPoll()
    }

    @discardableResult
    func apply(_ content: (type: String, text: String?, image: Data?, fileBookmarks: Data?, fileName: String?),
               context: ModelContext,
               correlationID cid: String) -> CaptureOutcome {
        // ── Image path (MD5 dedup) ──
        if content.type == "image", let imageData = content.image {
            if isDedupEnabled {
                let md5 = Self.md5Hash(imageData)
                let imagePredicate = #Predicate<ClipItem> { $0.contentTypeRaw == "image" && $0.imageMD5 == md5 }
                if let existing = try? context.fetch(FetchDescriptor<ClipItem>(predicate: imagePredicate)),
                   let existingItem = existing.first {
                    existingItem.timestamp = Date()
                    try? context.save()
                    NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
                    log.log(.dedup, .info, "image dedup hit", metadata: ["md5": String(md5.prefix(8))], correlationID: cid)
                    return .dedupedImage
                }
            }
            Self.enforceCap(context: context, maxCount: maxHistoryCount)
            let fileName = content.fileName ?? "\(workspace.appName ?? "未知")-\(UUID().uuidString.prefix(4))"
            let thumbnail = Self.generateThumbnail(imageData)
            let item = ClipItem(timestamp: Date(), contentTypeRaw: content.type,
                                imageData: imageData, imageThumbnail: thumbnail,
                                imageFileName: fileName, imageMD5: Self.md5Hash(imageData),
                                sourceAppBundleID: workspace.bundleID)
            context.insert(item)
            try? context.save()
            NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
            log.log(.store, .info, "inserted image", metadata: ["bytes": "\(imageData.count)"], correlationID: cid)
            return .inserted(type: "image")
        }

        // ── Text dedup vs latest ──
        if isDedupEnabled, content.type == "text",
           let latest = try? context.fetch(
               FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])).first,
           latest.contentTypeRaw == "text", latest.textContent == content.text {
            latest.timestamp = Date()
            try? context.save()
            NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
            log.log(.dedup, .info, "text dedup hit", correlationID: cid)
            return .dedupedText
        }

        // ── Insert (text / file) ──
        Self.enforceCap(context: context, maxCount: maxHistoryCount)
        let item = ClipItem(timestamp: Date(), contentTypeRaw: content.type,
                            textContent: content.text,
                            imageFileName: content.type == "file" ? content.fileName : nil,
                            fileBookmarks: content.fileBookmarks,
                            sourceAppBundleID: workspace.bundleID)
        context.insert(item)
        try? context.save()
        NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
        log.log(.store, .info, "inserted \(content.type)", correlationID: cid)
        return .inserted(type: content.type)
    }

    enum CaptureOutcome: Equatable {
        case skipped, dedupedText, dedupedImage, inserted(type: String)
    }
```

**(d)** Change `readPasteboard` signature from `private func readPasteboard(_ pb: NSPasteboard, ...)` to `func readPasteboard(_ pb: PasteboardReading, ...)` (drop `private`). Change `extractFileName(from pb: NSPasteboard, ...)` to `func extractFileName(from pb: PasteboardReading, ...)`. The bodies are unchanged (they already use only protocol methods).

**(e)** `observeSettings()` is unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/MonitorConstructionTests" 2>&1 | tail -20`
Then confirm the whole existing monitor suite still passes:
Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/ClipboardMonitorTests" 2>&1 | tail -20`
Expected: both PASS. (Existing tests call `ClipboardMonitor(settings:)` — still valid via defaults — and static helpers, unaffected.)

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Services/ClipboardMonitor.swift" "Mini CapsuleTests/Integration/SelfPasteTrackerTests.swift"
git commit -m "refactor(monitor): inject seams, split checkPasteboard into pollOnce/apply, add logging"
```

---

## Task 7: T2 capture-flow integration tests (feature 1)

**Files:**
- Create: `Mini CapsuleTests/Integration/CaptureFlowTests.swift`

**Interfaces:**
- Consumes: `ClipboardMonitor`, `CaptureOutcome`, `FakePasteboard`, `FakeWorkspace`, `SelfPasteTracker`, `InMemoryLogSink`, `MockSettingsForSeams` (from Task 6).

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/Integration/CaptureFlowTests.swift`:

```swift
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
        pb.stubbedChangeCount = 5
        pb.stubbedTypes = [.string]; pb.stubbedStrings[.string] = "should not store"
        let tracker = SelfPasteTracker()
        tracker.markRange(begin: 5, end: 5)   // pretend we produced changeCount 5
        let monitor = makeMonitor(pasteboard: pb, log: InMemoryLogSink(), selfPaste: tracker)
        monitor.start(context: ctx)

        monitor.pollOnce()

        #expect(try ctx.fetch(FetchDescriptor<ClipItem>()).isEmpty)   // suppressed, nothing stored
    }

    @Test func enforcesCapWhenInsertingOverLimit() throws {
        let ctx = try makeContext()
        // MockSettingsForSeams.historyMaxCount == 200; insert past it via a lower cap using many items.
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/CaptureFlowTests" 2>&1 | tail -20`
Expected: initially FAIL only if any assertion is wrong; since the implementation exists (Task 6), fix any mismatch until green. (If all pass immediately, that is acceptable — the value is the regression net.)

- [ ] **Step 3: Make green**

Run the suite; if `enforcesCapWhenInsertingOverLimit` is off by one, recall `enforceCap` removes `count - maxCount + 1` unpinned items to leave room — with 200 items at cap 200 it removes 1, then inserts 1, netting 200. Adjust the assertion to `#expect(items.count == 200)` if you prefer an exact check. No production change should be needed.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/CaptureFlowTests" 2>&1 | tail -20`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add "Mini CapsuleTests/Integration/CaptureFlowTests.swift"
git commit -m "test(integration): capture-flow tests for insert/dedup/suppress/cap (feature 1)"
```

---

## Task 8: Mark features 1 & 7 covered + full-suite verification

**Files:**
- Modify: `docs/testing/coverage-manifest.json`
- Modify: `docs/testing/traceability-matrix.md`

- [ ] **Step 1: Update the manifest**

In `docs/testing/coverage-manifest.json`, change feature 1 and feature 7 to `covered` with their new tests:

```json
    { "id": 1,  "name": "ClipboardMonitor — capture",      "tier": ["T2"],  "tests": ["CaptureFlowTests","MonitorConstructionTests"], "checklist": [], "status": "covered" },
```

```json
    { "id": 7,  "name": "HotKeyCenter",                     "tier": ["T2"],  "tests": ["HotKeyCenterIntegrationTests"], "checklist": ["M3","M4"], "status": "covered" },
```

Leave every other feature unchanged.

- [ ] **Step 2: Update the human matrix**

In `docs/testing/traceability-matrix.md`, update rows 1 and 7 to reflect the same tests and `covered` status.

- [ ] **Step 3: Verify the meta-gate still passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/MetaCoverageTests" 2>&1 | tail -20`
Expected: PASS — covered rows now link tests; pending rows still name their plan.

- [ ] **Step 4: Full-suite green run via the plan**

Run: `Scripts/run-tests.sh fast 2>&1 | tee /tmp/mc-plan2.log | tail -40`
Expected: exit 0. Confirm PASS for: all pre-existing suites, all Plan 1 logging suites, and the new `PasteboardSeamTests`, `SystemSeamTests`, `SelfPasteTrackerTests`, `PasteServiceSeamTests`, `HotKeyCenterIntegrationTests`, `MonitorConstructionTests`, `CaptureFlowTests`.

- [ ] **Step 5: Commit**

```bash
git add docs/testing/coverage-manifest.json docs/testing/traceability-matrix.md
git commit -m "test(meta): mark capture flow + hotkey (features 1,7) covered"
```

---

## Self-Review Notes (author)

- **Spec §7 seams** → Tasks 1–2 (pasteboard/system), Task 5 (scheduling/hotkey). **`SelfPasteTracker` extraction** → Task 3. **`PasteService` seam injection** → Task 4. **`checkPasteboard` decomposition (`classify`→outcome→`apply`)** → Task 6 (realized as `pollOnce`+`apply`+`CaptureOutcome`). **T2 integration** → Tasks 4, 5, 7.
- **Behavior preservation:** every refactor keeps existing call sites via default parameters; each task re-runs the affected pre-existing suite (`PasteServiceTests`, `HotKeyParserTests`, `ClipboardMonitorTests`) to prove no regression.
- **Deferred (consistent with the coverage manifest):** `readPasteboard` 10-tier unit backfill + dedup/cap/paste edge cases → Plan 3; `CapsuleViewModel` Scheduling seam + `SettingsStore` logging + remaining subsystems → Plan 4. `CapsuleViewModel`/`SettingsStore` are intentionally **not** touched here (manifest routes features 8 & 10 to Plan 4), narrowing this plan to the three hard services.
- **Naming consistency check:** `CaptureOutcome` cases (`skipped`/`dedupedText`/`dedupedImage`/`inserted(type:)`), `SelfPasteTracker.markRange(begin:end:)`/`shouldSuppress(changeCount:)`, `HotKeyRegistering.register(keyCode:modifiers:handler:)`, and the `ClipboardMonitor` init parameter order are used identically across defining and consuming tasks.
- **Privacy:** logging metadata carries only types/counts/md5-prefixes; no `text`/`image` bytes. A dedicated "no content in metadata" assertion is added in Plan 3 when readPasteboard tiers start logging.
```

